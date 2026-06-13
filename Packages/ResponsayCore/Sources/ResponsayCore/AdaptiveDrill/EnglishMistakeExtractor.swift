import Foundation

/// Connects the English coach to the drill engine: turns a coaching result into
/// drillable `MistakeRecord`s. A result that didn't actually change anything is
/// not a mistake, so it produces nothing.
public struct EnglishMistakeExtractor: Sendable {
    public init() {}

    /// From the rich 表达纠正 result (rewrite + why + ready practice prompts).
    public func extract(
        from result: ExpressionCorrectionResult,
        sourceText: String
    ) -> [MistakeRecord] {
        let rewritten = result.rewritten.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rewritten.isEmpty,
              rewritten != sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return [] }

        let category = result.why.first?.kind.title ?? "表达"
        return [MistakeRecord(
            id: MistakeRecord.contentID(category: category, prompt: sourceText, expected: result.rewritten),
            category: category,
            prompt: sourceText,
            expected: result.rewritten,
            explanation: result.why.map(\.text).joined(separator: "\n"),
            drillPrompts: result.practice)]
    }

    /// From a saved 错题本 capture (原话 → 地道版 + reasons).
    public func extract(from item: CaptureItem) -> [MistakeRecord] {
        let idiomatic = item.idiomatic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !idiomatic.isEmpty,
              idiomatic != item.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return [] }

        return [MistakeRecord(
            id: MistakeRecord.contentID(category: "表达", prompt: item.sourceText, expected: item.idiomatic),
            category: "表达",
            prompt: item.sourceText,
            expected: item.idiomatic,
            explanation: item.reasons.joined(separator: "\n"),
            createdAt: item.createdAt,
            sourceLanguage: item.language)]
    }
}
