import Foundation

public protocol CoachAPI: Sendable {
    func express(_ intent: String, context: ExpressionContext?) async throws -> ExpressionResult
    func ask(_ question: String, context: String) async throws -> ExpressionResult
    func analyze(_ sentence: String) async throws -> ProsodyAnalysis
}

public extension CoachAPI {
    func express(_ intent: String) async throws -> ExpressionResult {
        try await express(intent, context: nil)
    }
}

public enum CoachAPIError: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let m): return m }
    }
}
