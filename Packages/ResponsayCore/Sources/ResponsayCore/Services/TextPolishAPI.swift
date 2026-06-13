import Foundation

public protocol TextPolishAPI: Sendable {
    func polish(_ text: String) async throws -> PolishResult
}
