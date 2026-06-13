import Foundation

public struct DirectZhipuTranscriptionAPI: TranscriptionAPI {
    private let baseURL: URL
    private let session: URLSession
    private let maxAudioBytes: Int
    private let hotwordsProvider: @Sendable () -> [String]
    private let profileProvider: @Sendable () -> SpeechCaptureProfile
    private let modelProvider: @Sendable () -> String
    private let apiKeyProvider: @Sendable () -> String

    public init(
        baseURL: URL = URL(string: "https://open.bigmodel.cn/api/paas/v4")!,
        session: URLSession = .shared,
        maxAudioBytes: Int = 10_000_000,
        hotwordsProvider: @escaping @Sendable () -> [String] = { [] },
        profileProvider: @escaping @Sendable () -> SpeechCaptureProfile = { .dictation },
        modelProvider: @escaping @Sendable () -> String = { "glm-asr-2512" },
        apiKeyProvider: @escaping @Sendable () -> String = {
            (UserDefaults.standard.string(forKey: "zhipuKey") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.maxAudioBytes = maxAudioBytes
        self.hotwordsProvider = hotwordsProvider
        self.profileProvider = profileProvider
        self.modelProvider = modelProvider
        self.apiKeyProvider = apiKeyProvider
    }

    public func transcribe(audio: Data, mimeType: String, language: String) async throws -> TranscriptionResult {
        guard audio.count <= maxAudioBytes else {
            throw CoachAPIError.message("录音太长，请缩短后再试。")
        }
        
        let key = apiKeyProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw CoachAPIError.message("未配置智谱 GLM 的 API Key。请在设置中配置。")
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("audio/transcriptions"))
        request.httpMethod = "POST"
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120

        let profile = profileProvider()
        let hotwords = hotwordsProvider().joined(separator: ", ")
        var prompt = ""
        if profile == .faithful {
            prompt += "请尽量保持原样转写，不要添加标点符号或润色。"
        }
        if !hotwords.isEmpty {
            // ADR-0011: the weak hint must keep the never-insert guard — bias
            // recognition toward the terms, never inject unspoken words.
            prompt += " 以下是一些相关的热词或术语：\(hotwords)。只转写实际说出的内容，不要插入没有说过的词。"
        }

        let extensionName = mimeType.components(separatedBy: "/").last ?? "wav"
        let fileName = "audio.\(extensionName)"

        var body = Data()
        
        // file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n".data(using: .utf8)!)
        
        // model
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(modelProvider())\r\n".data(using: .utf8)!)
        
        // response_format
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("json\r\n".data(using: .utf8)!)
        
        // language
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(language)\r\n".data(using: .utf8)!)
        
        // prompt
        if !prompt.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(prompt)\r\n".data(using: .utf8)!)
        }
        
        // closing boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CoachAPIError.message("Zhipu ASR 网络错误")
        }
        guard (200..<300).contains(http.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? ""
            throw CoachAPIError.message("Zhipu ASR \(http.statusCode): \(errorText.prefix(200))")
        }

        let json = try JSONDecoder().decode(ZhipuResponse.self, from: data)
        let text = json.text ?? ""
        if text.isEmpty {
            throw CoachAPIError.message("Zhipu ASR 返回为空")
        }

        return TranscriptionResult(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            model: modelProvider(),
            language: language,
            provider: "zhipu"
        )
    }
}

private struct ZhipuResponse: Decodable {
    let text: String?
}
