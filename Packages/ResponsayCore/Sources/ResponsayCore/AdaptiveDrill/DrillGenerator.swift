import Foundation

/// Turns a `MistakeRecord` into a presentable `DrillItem`. A seam: the default
/// is deterministic + offline (reuses the cue/answer the coach already produced);
/// an LLM-backed generator can conform later without touching the session loop.
public protocol DrillGenerating: Sendable {
    func makeDrill(from mistake: MistakeRecord, difficulty: DrillDifficulty) -> DrillItem
}

/// Offline, template-based generator. Difficulty controls how much help shows
/// (easy reveals the explanation / first practice cue; hard hides it).
public struct TemplateDrillGenerator: DrillGenerating {
    public init() {}

    public func makeDrill(from mistake: MistakeRecord, difficulty: DrillDifficulty) -> DrillItem {
        DrillItem(
            mistakeID: mistake.id,
            question: "用更地道的说法表达:「\(mistake.prompt)」",
            expectedAnswer: mistake.expected,
            hint: hint(for: mistake, difficulty: difficulty),
            difficulty: difficulty)
    }

    /// Only the easy rung gets a hint, so improving learners face desirable difficulty.
    private func hint(for mistake: MistakeRecord, difficulty: DrillDifficulty) -> String? {
        guard difficulty == .easy else { return nil }
        if !mistake.explanation.isEmpty { return mistake.explanation }
        return mistake.drillPrompts.first
    }
}
