import Foundation

/// One hotword entry in a DashScope vocabulary (custom-hot-words-user-guide).
public struct DashScopeHotword: Codable, Sendable, Equatable {
    public let text: String
    public let weight: Int
    public let lang: String?

    public init(text: String, weight: Int = 4, lang: String? = nil) {
        self.text = text
        self.weight = weight
        self.lang = lang
    }
}

/// REST client for the DashScope hotword-vocabulary resource
/// (`POST /api/v1/services/audio/asr/customization`, model `speech-biasing`).
/// Live-verified 2026-06-11: create → vocabulary_id → recognition with the id
/// corrected "response" → "Responsay" on fun-asr-realtime.
public struct DashScopeVocabularyClient: Sendable {
    public enum Failure: Error { case http(Int, String), badResponse }

    private let baseURL: URL
    private let session: URLSession
    private let apiKeyProvider: @Sendable () -> String

    public init(
        baseURL: URL = URL(string: "https://dashscope.aliyuncs.com/api/v1")!,
        session: URLSession = .shared,
        apiKeyProvider: @escaping @Sendable () -> String
    ) {
        self.baseURL = baseURL
        self.session = session
        self.apiKeyProvider = apiKeyProvider
    }

    /// Create a vocabulary for `targetModel`; returns the `vocabulary_id`.
    /// The recognition call must use the *same* model or hotwords are inert.
    public func createVocabulary(
        targetModel: String, prefix: String, vocabulary: [DashScopeHotword]
    ) async throws -> String {
        let input: [String: Any] = [
            "action": "create_vocabulary",
            "target_model": targetModel,
            "prefix": prefix,
            "vocabulary": vocabulary.map { word -> [String: Any] in
                var obj: [String: Any] = ["text": word.text, "weight": word.weight]
                if let lang = word.lang { obj["lang"] = lang }
                return obj
            },
        ]
        let output = try await post(input: input)
        guard let id = output["vocabulary_id"] as? String, !id.isEmpty else {
            throw Failure.badResponse
        }
        return id
    }

    public func deleteVocabulary(id: String) async throws {
        _ = try await post(input: ["action": "delete_vocabulary", "vocabulary_id": id])
    }

    /// List vocabulary ids whose name carries `prefix` (quota recovery: the
    /// account holds at most 10 vocabularies across all models).
    public func listVocabularyIDs(prefix: String) async throws -> [String] {
        let output = try await post(input: ["action": "list_vocabulary", "prefix": prefix])
        let entries = output["vocabulary_list"] as? [[String: Any]] ?? []
        return entries.compactMap { $0["vocabulary_id"] as? String }
    }

    private func post(input: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: baseURL.appendingPathComponent("services/audio/asr/customization"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKeyProvider())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["model": "speech-biasing", "input": input])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw Failure.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return root?["output"] as? [String: Any] ?? [:]
    }
}
