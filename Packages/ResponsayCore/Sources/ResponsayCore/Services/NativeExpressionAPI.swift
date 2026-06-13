import Foundation

/// 140 — 中文意图 → 地道英文 teaching action. A **distinct route** from the
/// pure-rewrite 改写 (`PolishQuietAPI`, 137): the input is a Chinese intent and
/// the result keeps its `why` coaching.
public protocol NativeExpressionAPI: Sendable {
    func express(_ request: NativeExpressionRequest) async throws -> NativeExpressionResult
}
