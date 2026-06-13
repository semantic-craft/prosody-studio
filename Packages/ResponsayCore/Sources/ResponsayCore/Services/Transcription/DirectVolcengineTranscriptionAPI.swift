import Foundation

/// 火山引擎 (豆包语音) 整段识别 — 同一 SAUC 大模型产品的 `bigmodel_nostream`
/// WebSocket 路径：一次性推完整段音频，服务端返回单个 final。与流式共用
/// APP ID / Access Token / Resource ID（不是独立的「录音文件识别」产品，后者
/// 走 file_urls 异步提交且需单独开通资源）。自 2026-06-11 起不再是独立的
/// picker 引擎，仅作为整段消费方（练习跟读等）的批量转写后端。
///
/// 热词同流式走 `request.corpus`（nostream 直传预算 5 000 词，词表 ID 优先）。
public struct DirectVolcengineTranscriptionAPI: TranscriptionAPI {
    private let session: URLSession
    private let appIdProvider: @Sendable () -> String
    private let accessTokenProvider: @Sendable () -> String
    private let hotwordsProvider: @Sendable () -> [String]
    private let boostingTableIDProvider: @Sendable () -> String?

    public init(
        session: URLSession = .shared,
        appIdProvider: @escaping @Sendable () -> String,
        accessTokenProvider: @escaping @Sendable () -> String,
        hotwordsProvider: @escaping @Sendable () -> [String] = { [] },
        boostingTableIDProvider: @escaping @Sendable () -> String? = { nil }
    ) {
        self.session = session
        self.appIdProvider = appIdProvider
        self.accessTokenProvider = accessTokenProvider
        self.hotwordsProvider = hotwordsProvider
        self.boostingTableIDProvider = boostingTableIDProvider
    }

    public func transcribe(audio: Data, mimeType: String, language: String) async throws -> TranscriptionResult {
        let appId = appIdProvider()
        let accessToken = accessTokenProvider()
        guard !appId.isEmpty && !accessToken.isEmpty else {
            throw CoachAPIError.message("请先在「模型与密钥 › ASR」中填写豆包语音的 APP ID 和 Access Token。")
        }

        let url = URL(string: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream")!
        var request = URLRequest(url: url)
        // X-Api-Access-Key form (openless parity; server 400s the old
        // `Authorization: Bearer; ` form — live-verified, issue 316).
        request.setValue(accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(appId, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(VolcengineCredentials.defaultResourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        let connectID = UUID().uuidString
        request.setValue(connectID, forHTTPHeaderField: "X-Api-Connect-Id")
        
        let connection = URLSessionVolcengineWebSocket(request: request, session: session)
        
        let format = mimeType.contains("m4a") || mimeType.contains("mp4") ? "m4a" : "wav"
        var requestBody: [String: Any] = [
            "reqid": connectID,
            "model_name": "bigmodel",
            "enable_itn": true,
            "enable_punc": true
        ]
        let hotwords = hotwordsProvider().map { VolcengineHotword(phrase: $0, enabled: true) }
        if let corpus = VolcengineASRProtocol.corpus(
            hotwords: hotwords,
            boostingTableID: boostingTableIDProvider(),
            cap: VolcengineASRProtocol.hotwordCapNostream) {
            requestBody["corpus"] = corpus
        }
        let reqPayload: [String: Any] = [
            "user": ["uid": "responsay-mac"],
            "audio": [
                "format": format,
                "codec": "raw", // HTTP submit logic used codec: "raw" with m4a format
                "rate": 16000,
                "bits": 16,
                "channel": 1
            ],
            "request": requestBody
        ]
        
        let reqData = try JSONSerialization.data(withJSONObject: reqPayload)
        
        // 1. Send FullClientRequest
        let reqFrame = VolcengineASRFrame.build(
            messageType: .fullClientRequest,
            flags: .positiveSequence,
            serialization: .json,
            payload: reqData,
            sequence: 1
        )
        try await connection.send(reqFrame)
        
        // 2. Send Audio chunks
        let chunkSize = 6400
        var offset = 0
        var seq: Int32 = 2
        while offset < audio.count {
            let end = min(offset + chunkSize, audio.count)
            let chunk = audio.subdata(in: offset..<end)
            let isLast = end >= audio.count
            let audioFrame = VolcengineASRFrame.build(
                messageType: .audioOnlyRequest,
                flags: isLast ? .negativeSequence : .positiveSequence,
                serialization: .none,
                payload: chunk,
                sequence: isLast ? -seq : seq
            )
            try await connection.send(audioFrame)
            seq += 1
            offset = end
        }
        
        // 3. Receive till stream end
        var finalText = ""
        while true {
            let data: Data
            do {
                data = try await connection.receive()
            } catch {
                connection.cancel()
                throw CoachAPIError.message("火山引擎 ASR 网络错误: \(error.localizedDescription)")
            }
            
            guard let parsed = VolcengineASRFrame.parse(data) else { continue }
            
            if parsed.messageType == .errorMessage {
                connection.cancel()
                if let errJSON = try? JSONSerialization.jsonObject(with: parsed.payload) as? [String: Any],
                   let msg = errJSON["message"] as? String {
                    throw CoachAPIError.message("火山引擎 ASR 错误: \(msg)")
                }
                throw CoachAPIError.message("火山引擎 ASR 内部错误 [\(parsed.errorCode ?? 0)]")
            }
            
            if parsed.messageType == .fullServerResponse {
                if let text = VolcengineASRProtocol.transcriptText(fromServerJSON: parsed.payload) {
                    // No result_type is sent, so the server defaults to "full"
                    // (cumulative) responses — each one carries the complete
                    // text so far. Replace, never append, or multi-response
                    // clips (>15 s) would duplicate every earlier chunk.
                    finalText = text
                }
            }
            
            if parsed.isFinal {
                break
            }
        }
        
        connection.cancel()
        
        if finalText.isEmpty {
            throw CoachAPIError.message("火山引擎 ASR 返回文本为空")
        }
        
        return TranscriptionResult(
            text: finalText.trimmingCharacters(in: .whitespacesAndNewlines),
            model: "bigmodel",
            language: language,
            provider: "volc-asr"
        )
    }
}
