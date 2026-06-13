import Foundation

/// Whole-clip transcription on top of the fun-asr-realtime WebSocket: pump the
/// PCM at full speed, collect sentence finals, return the joined text.
///
/// Why not the documented "non-realtime" API: that one is an async file-
/// transcription service that only accepts *public* `file_urls` (submit →
/// poll → download), built for hours-long recordings. Uploading local
/// dictation audio somewhere public would add latency and break the privacy
/// story. Pumping the streaming socket faster than real time was live-verified
/// 2026-06-11: complete final, hotwords honored, faster than real time.
/// This also means batch and realtime share one model — one hotword
/// vocabulary (target_model fun-asr-realtime) covers both.
public struct FunASRBatchTranscriptionAPI: TranscriptionAPI {
    private let endpoint: FunASRRealtimeEndpoint
    private let session: URLSession
    private let apiKeyProvider: @Sendable () -> String
    private let vocabularyIDProvider: @Sendable () async -> String?

    public init(
        endpoint: FunASRRealtimeEndpoint = FunASRRealtimeEndpoint(),
        session: URLSession = .shared,
        apiKeyProvider: @escaping @Sendable () -> String,
        vocabularyIDProvider: @escaping @Sendable () async -> String? = { nil }
    ) {
        self.endpoint = endpoint
        self.session = session
        self.apiKeyProvider = apiKeyProvider
        self.vocabularyIDProvider = vocabularyIDProvider
    }

    public func transcribe(audio: Data, mimeType: String, language: String) async throws -> TranscriptionResult {
        let key = apiKeyProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw CoachAPIError.message("Fun-ASR 整段识别缺少 API Key。请在「设置 › 听写 ASR」中配置通义千问密钥。")
        }
        let pcm = Self.pcmPayload(from: audio, mimeType: mimeType)
        guard !pcm.isEmpty else {
            throw CoachAPIError.message("音频为空，无法识别。")
        }

        var request = URLRequest(url: endpoint.url)
        request.setValue("bearer \(key)", forHTTPHeaderField: "Authorization")
        let ws = session.webSocketTask(with: request)
        ws.resume()
        defer { ws.cancel(with: .normalClosure, reason: nil) }

        let client = FunASRRealtimeClient(
            transport: ws, taskID: UUID().uuidString.replacingOccurrences(of: "-", with: ""))
        try await client.sendRunTask(endpoint: endpoint, vocabularyID: await vocabularyIDProvider())

        // Wait for task-started, then pump at full speed and finish.
        var finals: [String] = []
        var started = false
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            let event = try await client.receive()
            switch event {
            case .taskStarted:
                guard !started else { continue }
                started = true
                var offset = 0
                let chunk = 3200
                while offset < pcm.count {
                    let end = min(offset + chunk, pcm.count)
                    try await client.sendAudio(pcm.subdata(in: offset..<end))
                    offset = end
                }
                try await client.sendFinishTask()
            case .result(let sentence):
                if sentence.sentenceEnd, !sentence.text.isEmpty {
                    finals.append(sentence.text)
                }
            case .taskFinished:
                return TranscriptionResult(
                    text: finals.joined(), model: endpoint.model,
                    language: language, provider: "qwen-fun-asr")
            case .taskFailed(let code, let message):
                throw CoachAPIError.message("Fun-ASR 识别失败 [\(code)]: \(message)")
            case .heartbeat, .unknown:
                continue
            }
        }
        throw CoachAPIError.message("Fun-ASR 识别超时，请重试。")
    }

    /// Accepts WAV (header stripped by scanning for the `data` chunk) or raw
    /// 16k/16-bit/mono PCM.
    static func pcmPayload(from audio: Data, mimeType: String) -> Data {
        guard audio.count > 12, audio.prefix(4) == Data("RIFF".utf8) else { return audio }
        var offset = 12
        while offset + 8 <= audio.count {
            let chunkID = audio.subdata(in: offset..<offset + 4)
            let size = audio.subdata(in: offset + 4..<offset + 8).withUnsafeBytes {
                Int($0.loadUnaligned(as: UInt32.self).littleEndian)
            }
            if chunkID == Data("data".utf8) {
                let start = offset + 8
                let end = min(start + size, audio.count)
                return audio.subdata(in: start..<end)
            }
            offset += 8 + size
        }
        return audio
    }
}
