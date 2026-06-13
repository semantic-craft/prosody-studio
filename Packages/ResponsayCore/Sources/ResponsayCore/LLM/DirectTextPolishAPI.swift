import Foundation

/// App-direct 轻改写 (tracer 239, epic 238): builds the polish prompt on the client and calls
/// the BYOK provider's OpenAI-compatible endpoint straight — no backend hop. Conforms to the
/// same `TextPolishAPI` the backend client (`HTTPTextPolishAPI`) did, so call sites swap
/// transparently; the app picks Direct vs HTTP by whether the LLM card is configured.
public struct DirectTextPolishAPI: TextPolishAPI {
    let endpoint: LLMEndpoint
    let client: LLMChatClient

    public init(endpoint: LLMEndpoint, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.client = LLMChatClient(session: session)
    }

    public func polish(_ text: String) async throws -> PolishResult {
        let prompt = PolishPromptBuilder.build(text: text)
        let request = try LLMChatRequestBuilder.makeRequest(
            endpoint: endpoint, system: prompt.system, user: prompt.user,
            responseFormat: LLMResponseFormat.textChanges,
            generationAction: .polish)
        let raw = try await client.execute(request)
        guard let obj = LLMResponseParsing.jsonObject(from: raw) else {
            throw LLMError.badJSON(String(raw.prefix(200)))
        }
        let outText = LLMResponseParsing.string(obj, "text")
        guard !outText.isEmpty else { throw LLMError.badJSON("missing \"text\"") }
        // The model's {text, changes} envelope has no "original" — fill it from the input.
        return PolishResult(
            text: outText,
            original: text,
            changes: LLMResponseParsing.stringArray(obj, "changes"))
    }
}
