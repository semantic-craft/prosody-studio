import Foundation

/// One presentable practice item generated from a `MistakeRecord`. English
/// production recall: show the cue, the learner produces the idiomatic form.
public struct DrillItem: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let mistakeID: UUID
    /// The cue shown to the learner.
    public let question: String
    /// The idiomatic form to recall (graded against the answer).
    public let expectedAnswer: String
    /// Shown only at lower difficulty (less help as you improve).
    public let hint: String?
    public let difficulty: DrillDifficulty

    public init(
        id: UUID = UUID(),
        mistakeID: UUID,
        question: String,
        expectedAnswer: String,
        hint: String? = nil,
        difficulty: DrillDifficulty
    ) {
        self.id = id
        self.mistakeID = mistakeID
        self.question = question
        self.expectedAnswer = expectedAnswer
        self.hint = hint
        self.difficulty = difficulty
    }
}
