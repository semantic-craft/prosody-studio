import Foundation

/// Outcome of grading one answer.
public enum DrillGrade: String, Sendable, Equatable {
    case correct
    case incorrect
}

/// Grades a submitted answer for a `DrillItem`. A seam: the default is an
/// offline lenient string match; an LLM grader can conform later.
public protocol DrillGrading: Sendable {
    func grade(answer: String, for item: DrillItem) -> DrillGrade
}

/// Offline grader: lenient match (case / punctuation / whitespace insensitive).
public struct DrillAnswerGrader: DrillGrading {
    public init() {}

    public func grade(answer: String, for item: DrillItem) -> DrillGrade {
        Self.normalize(answer) == Self.normalize(item.expectedAnswer) ? .correct : .incorrect
    }

    static func normalize(_ text: String) -> String {
        let strip = CharacterSet(charactersIn: " \t\n.,!?;:\"'`()[]{}。，！？；：、「」『』（）“”‘’")
        let folded = text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        return String(folded.unicodeScalars.filter { !strip.contains($0) })
    }
}
