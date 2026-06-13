import Foundation

/// App-direct English coach (242 express + 244 analyze, epic 238): builds the express /
/// prosody prompts on the client and calls the BYOK provider straight. Conforms to the same
/// `CoachAPI` the backend client did. `register` (教练语域) is supplied by the app from settings.
public struct DirectCoachAPI: CoachAPI {
    let endpoint: LLMEndpoint
    let register: CoachRegister
    let client: LLMChatClient

    public init(endpoint: LLMEndpoint, register: CoachRegister, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.register = register
        self.client = LLMChatClient(session: session)
    }

    public func express(_ intent: String, context: ExpressionContext?) async throws -> ExpressionResult {
        let prompt = ExpressPromptBuilder.build(intent: intent, context: context, register: register)
        let request = try LLMChatRequestBuilder.makeRequest(
            endpoint: endpoint, system: prompt.system, user: prompt.user,
            responseFormat: LLMResponseFormat.express,
            generationAction: .express)
        let raw = try await client.execute(request)
        guard let obj = LLMResponseParsing.jsonObject(from: raw) else {
            throw LLMError.badJSON(String(raw.prefix(200)))
        }
        let idiomatic = LLMResponseParsing.string(obj, "idiomatic")
        guard !idiomatic.isEmpty else { throw LLMError.badJSON("missing \"idiomatic\"") }
        return ExpressionResult(
            idiomatic: idiomatic,
            original: intent,
            reasons: LLMResponseParsing.stringArray(obj, "reasons"),
            thinkingShift: LLMResponseParsing.string(obj, "thinkingShift"),
            alternatives: LLMResponseParsing.stringArray(obj, "alternatives"))
    }

    public func ask(_ question: String, context: String) async throws -> ExpressionResult {
        let system = "你是一个智能助手。请基于以下提供的参考上下文，回答用户的问题。"
        let user = """
        [上下文开始]
        \(context)
        [上下文结束]
        问题：\(question)
        """
        let request = try LLMChatRequestBuilder.makeRequest(
            endpoint: endpoint, system: system, user: user,
            responseFormat: LLMResponseFormat.express,
            generationAction: .ask)
        let raw = try await client.execute(request)
        guard let obj = LLMResponseParsing.jsonObject(from: raw) else {
            throw LLMError.badJSON(String(raw.prefix(200)))
        }
        let idiomatic = LLMResponseParsing.string(obj, "idiomatic")
        guard !idiomatic.isEmpty else { throw LLMError.badJSON("missing \"idiomatic\"") }
        return ExpressionResult(
            idiomatic: idiomatic,
            original: question,
            reasons: LLMResponseParsing.stringArray(obj, "reasons"),
            thinkingShift: "",
            alternatives: [])
    }

    public func analyze(_ sentence: String) async throws -> ProsodyAnalysis {
        let prompt = ProsodyPromptBuilder.build(text: sentence)
        let request = try LLMChatRequestBuilder.makeRequest(
            endpoint: endpoint, system: prompt.system, user: prompt.user,
            generationAction: .prosody)
        let raw = try await client.execute(request)
        guard let data = LLMResponseParsing.jsonData(from: raw) else {
            throw LLMError.badJSON(String(raw.prefix(200)))
        }
        do {
            let decoded = try JSONDecoder().decode(ProsodyAnalysis.self, from: data)
            return try Self.validateRepairAndNormalize(decoded)
        } catch {
            throw LLMError.badJSON("prosody decode/validation failed")
        }
    }

    private static func validateRepairAndNormalize(_ analysis: ProsodyAnalysis) throws -> ProsodyAnalysis {
        let structurallyValid: ProsodyAnalysis
        do {
            try ProsodyValidator.validateProsody(analysis)
            structurallyValid = analysis
        } catch {
            let repaired = try ProsodyValidator.repairProsodyShape(analysis)
            try ProsodyValidator.validateProsody(repaired)
            structurallyValid = repaired
        }

        let normalized = ProsodyValidator.normalizeProsodyForEverydayEnglish(structurallyValid)
        try ProsodyValidator.validateProsody(normalized)
        return normalized
    }
}
