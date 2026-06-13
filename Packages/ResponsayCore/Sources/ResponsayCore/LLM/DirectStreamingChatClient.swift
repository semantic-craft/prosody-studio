import Foundation

/// A generic streaming chat client that accepts a raw array of messages.
/// Used by the Global Voice Assistant for multi-turn conversations.
public final class DirectStreamingChatClient: Sendable {
    private let endpoint: LLMEndpoint
    private let session: URLSession
    private let parser = OpenAIStreamLineParser()

    public init(endpoint: LLMEndpoint, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    public func stream(messages: [[String: String]]) -> AsyncThrowingStream<TextStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [endpoint, session, parser, messages] in
                do {
                    guard endpoint.isConfigured else {
                        continuation.finish(throwing: LLMError.notConfigured); return
                    }
                    guard let url = LLMWire.chatCompletionsURL(base: endpoint.baseURL) else {
                        continuation.finish(throwing: LLMError.invalidEndpoint(endpoint.baseURL)); return
                    }
                    
                    var body: [String: Any] = [
                        "model": endpoint.model,
                        "messages": messages,
                        "stream": true,
                    ]
                    
                    for (key, value) in LLMThinkingControl.extraBody(
                        providerId: endpoint.providerId, model: endpoint.model,
                        baseURLHost: endpoint.host, enabled: endpoint.thinkingEnabled, streaming: true) {
                        body[key] = value
                    }
                    for (key, value) in LLMStreamOptionsControl.extraBody(
                        providerId: endpoint.providerId, baseURLHost: endpoint.host) {
                        body[key] = value
                    }

                    var urlRequest = URLRequest(url: url)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    for (key, value) in LLMWire.authHeaders(providerId: endpoint.providerId, key: endpoint.apiKey) {
                        urlRequest.setValue(value, forHTTPHeaderField: key)
                    }
                    urlRequest.timeoutInterval = endpoint.isLocal ? 300 : 60
                    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                        let errorBody = String(decoding: try await bytes.reduce(into: [UInt8]()) { $0.append($1) }, as: UTF8.self)
                        continuation.finish(throwing: LLMError.http(status: code, body: errorBody))
                        return
                    }
                    
                    var lineBuffer = [UInt8]()
                    for try await byte in bytes {
                        if byte != 0x0A { lineBuffer.append(byte); continue }
                        let line = String(decoding: lineBuffer, as: UTF8.self)
                        lineBuffer.removeAll(keepingCapacity: true)
                        guard let event = parser.event(for: line) else { continue }
                        continuation.yield(event)
                        if case .delta = event { continue }
                        continuation.finish()
                        return
                    }
                    if !lineBuffer.isEmpty,
                       let event = parser.event(for: String(decoding: lineBuffer, as: UTF8.self)) {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
