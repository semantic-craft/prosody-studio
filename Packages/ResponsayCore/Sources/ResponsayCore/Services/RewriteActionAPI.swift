import Foundation

/// 137 — 改写 (pure rewrite). Backend returns only `rewritten`.
public protocol PolishQuietAPI: Sendable {
    func polishQuiet(_ request: PolishQuietRequest) async throws -> PolishQuietResult
}

/// 138 — 表达纠正 (rewrite + teach). Returns rewrite + issues + why + practice.
public protocol ExpressionCorrectionAPI: Sendable {
    func correct(_ request: ExpressionCorrectionRequest) async throws -> ExpressionCorrectionResult
}
