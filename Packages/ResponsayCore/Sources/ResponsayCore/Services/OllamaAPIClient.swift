import Foundation

public struct OllamaPullProgress: Decodable, Sendable {
    public let status: String
    public let digest: String?
    public let total: Int64?
    public let completed: Int64?
}

public struct OllamaTagsResponse: Decodable, Sendable {
    public struct Model: Decodable, Sendable {
        public let name: String
        public let size: Int64
    }
    public let models: [Model]
}

/// A direct Swift client to manage the local Ollama daemon.
/// Handles checking for models and pulling them with progress reporting.
public struct OllamaAPIClient: Sendable {
    public static let shared = OllamaAPIClient()
    private let baseURL = URL(string: "http://localhost:11434/api")!
    
    public init() {}
    
    public enum Status: Equatable, Sendable {
        case notRunning
        case missingModel
        case ready(size: Int64)
    }
    
    /// Probes localhost:11434 to check if Ollama is alive and if a specific model tag exists.
    public func checkStatus(modelTag: String) async -> Status {
        var req = URLRequest(url: baseURL.appendingPathComponent("tags"))
        req.timeoutInterval = 2.0
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .notRunning
            }
            let res = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            if let found = res.models.first(where: { $0.name == modelTag }) {
                return .ready(size: found.size)
            }
            return .missingModel
        } catch {
            return .notRunning
        }
    }
    
    /// Pulls a model via Ollama's streaming NDJSON API.
    public func pullModel(name: String) -> AsyncThrowingStream<OllamaPullProgress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var req = URLRequest(url: baseURL.appendingPathComponent("pull"))
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let payload: [String: Any] = ["name": name, "stream": true]
                req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
                req.timeoutInterval = 60 * 60 // 1 hour max for big models
                
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        throw URLError(.badServerResponse)
                    }
                    
                    for try await line in bytes.lines {
                        guard let data = line.data(using: .utf8), !data.isEmpty else { continue }
                        let progress = try JSONDecoder().decode(OllamaPullProgress.self, from: data)
                        continuation.yield(progress)
                        if progress.status == "success" {
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}
