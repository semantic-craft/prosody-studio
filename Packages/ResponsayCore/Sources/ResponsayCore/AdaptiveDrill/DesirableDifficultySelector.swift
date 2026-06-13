import Foundation

/// Drill difficulty rung. `i+1` desirable difficulty moves one step at a time.
public enum DrillDifficulty: Int, Codable, Sendable, CaseIterable, Comparable {
    case easy = 1
    case medium = 2
    case hard = 3

    public static func < (lhs: DrillDifficulty, rhs: DrillDifficulty) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    func harder() -> DrillDifficulty { DrillDifficulty(rawValue: rawValue + 1) ?? .hard }
    func easier() -> DrillDifficulty { DrillDifficulty(rawValue: rawValue - 1) ?? .easy }
}

/// Picks the next difficulty to keep the learner in the "desirable difficulty"
/// band (fluent methodology): hold inside `[targetLow, targetHigh]`, step down
/// below it, step up above it — i.e. below 60% gets easier, above 80% gets
/// harder. Pure; clamps at the ends.
public struct DesirableDifficultySelector: Sendable {
    public let targetLow: Double
    public let targetHigh: Double

    public init(targetLow: Double = 0.60, targetHigh: Double = 0.80) {
        self.targetLow = targetLow
        self.targetHigh = targetHigh
    }

    public func next(current: DrillDifficulty, successRate: Double) -> DrillDifficulty {
        if successRate < targetLow { return current.easier() }
        if successRate > targetHigh { return current.harder() }
        return current
    }
}
