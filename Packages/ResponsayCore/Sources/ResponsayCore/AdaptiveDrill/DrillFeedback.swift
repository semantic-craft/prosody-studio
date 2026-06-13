import Foundation

/// Immediate feedback shown after an answer (fluent: corrections within seconds
/// + explanation). Severity drives the 🟢/🔴-style affordance in the UI.
public struct DrillFeedback: Sendable, Equatable {
    public enum Severity: String, Sendable, Equatable {
        case good   // correct
        case miss   // incorrect
    }

    public let grade: DrillGrade
    public let correctAnswer: String
    public let explanation: String
    public let severity: Severity

    public init(grade: DrillGrade, correctAnswer: String, explanation: String) {
        self.grade = grade
        self.correctAnswer = correctAnswer
        self.explanation = explanation
        self.severity = grade == .correct ? .good : .miss
    }
}
