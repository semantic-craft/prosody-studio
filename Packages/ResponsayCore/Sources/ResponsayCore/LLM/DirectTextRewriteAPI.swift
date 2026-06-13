import Foundation

/// App-direct 重改写 (tracer 239, epic 238): builds the rewrite prompt on the client and calls
/// the BYOK provider's OpenAI-compatible endpoint straight — no backend hop. Conforms to the
/// same `TextRewriteAPI` the backend client (`HTTPTextRewriteAPI`) did, so call sites swap
/// transparently; the app picks Direct vs HTTP by whether the LLM card is configured.
public struct DirectTextRewriteAPI: TextRewriteAPI {
    let endpoint: LLMEndpoint
    let client: LLMChatClient

    public init(endpoint: LLMEndpoint, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.client = LLMChatClient(session: session)
    }

    public func rewrite(_ text: String, style: RewriteStyle) async throws -> PolishResult {
        let prompt = RewritePromptBuilder.build(text: text, style: style)
        let request = try LLMChatRequestBuilder.makeRequest(
            endpoint: endpoint, system: prompt.system, user: prompt.user,
            responseFormat: LLMResponseFormat.textChanges,
            generationAction: .rewrite)
        let raw = try await client.execute(request)
        guard let obj = LLMResponseParsing.jsonObject(from: raw) else {
            throw LLMError.badJSON(String(raw.prefix(200)))
        }
        let outText = LLMResponseParsing.string(obj, "text")
        guard !outText.isEmpty else { throw LLMError.badJSON("missing \"text\"") }
        // The model's {text, changes} envelope has no "original" — fill it from the input,
        // matching how `PolishResult` is shaped elsewhere.
        return PolishResult(
            text: outText,
            original: text,
            changes: LLMResponseParsing.stringArray(obj, "changes"))
    }
}
