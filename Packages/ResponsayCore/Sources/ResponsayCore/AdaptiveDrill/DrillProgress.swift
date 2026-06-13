import Foundation

/// Per-mistake learning state: how often it was practiced (frequency) plus its
/// SM-2 spacing. Mastery is derived the same way `ReviewCard` does, so the two
/// surfaces stay consistent.
public struct DrillProgress: Codable, Sendable, Equatable {
    public let mistakeID: UUID
    public let attempts: Int
    public let successes: Int
    public let dueAt: Date
    public let intervalDays: Int
    public let repetitions: Int
    public let easeFactor: Double

    public init(
        mistakeID: UUID,
        attempts: Int = 0,
        successes: Int = 0,
        dueAt: Date,
        intervalDays: Int = 0,
        repetitions: Int = 0,
        easeFactor: Double = SM2Scheduler.defaultEaseFactor
    ) {
        self.mistakeID = mistakeID
        self.attempts = attempts
        self.successes = successes
        self.dueAt = dueAt
        self.intervalDays = intervalDays
        self.repetitions = repetitions
        self.easeFactor = easeFactor
    }

    public var successRate: Double {
        attempts == 0 ? 0 : Double(successes) / Double(attempts)
    }

    /// 1–5, shares `MasteryStars` with `ReviewCard`.
    public var masteryStars: Int {
        MasteryStars.rating(repetitions: repetitions, easeFactor: easeFactor)
    }
}
