import Foundation

public protocol TextTranslationAPI: Sendable {
    func translate(_ text: String, target: TranslationTargetLanguage) async throws -> TranslationResult
}
