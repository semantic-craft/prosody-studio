import Foundation

// MARK: - 106 LegalSkillExecutorAPI
//
// Separate from `CoachAPI` (which stays express/analyze). Production executor is
// `RoutingLegalSkillExecutor` (app-direct, ADR-0029: cloud → BYOK provider,
// localOnly → local Ollama); the original backend `/legal/skill/execute` route and
// its `localhost:8787` config are retired. `searchVerification` is optional and
// app-direct: callers only expose it when the resolved provider supports web search.

public protocol LegalSkillExecutorAPI: Sendable {
    func executeSkill(_ request: LegalSkillExecutionRequest) async throws -> LegalSkillExecutionResponse
    /// Optional LLM-search source/fact verification for a pending anchor.
    func searchVerification(_ anchor: VerificationAnchor, route: ModelRoute) async throws -> VerifiedSource?
    func supportsSearchVerification(route: ModelRoute) -> Bool
}

public extension LegalSkillExecutorAPI {
    func searchVerification(_ anchor: VerificationAnchor, route: ModelRoute) async throws -> VerifiedSource? {
        throw LegalSkillRuntimeError.executorNotImplemented(skillId: "legal.verification.search")
    }

    func supportsSearchVerification(route: ModelRoute) -> Bool { false }
}
