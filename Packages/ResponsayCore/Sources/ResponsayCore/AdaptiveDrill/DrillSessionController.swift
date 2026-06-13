import Foundation
import Observation

/// Runs one adaptive English drill session: present → answer → immediate
/// feedback → adapt difficulty → next (interleaved), to finish. Pure
/// collaborators are injected so the loop is fully unit-testable; the UI just
/// renders this.
@MainActor
@Observable
public final class DrillSessionController {
    public private(set) var current: DrillItem?
    public private(set) var lastFeedback: DrillFeedback?
    public private(set) var answered = 0
    public private(set) var correct = 0
    public private(set) var difficulty: DrillDifficulty
    public private(set) var isFinished = false

    private let queue: [MistakeRecord]
    private var index = 0
    private let generator: DrillGenerating
    private let grader: DrillGrading
    private let selector: DesirableDifficultySelector

    public init(
        mistakes: [MistakeRecord],
        generator: DrillGenerating = TemplateDrillGenerator(),
        grader: DrillGrading = DrillAnswerGrader(),
        interleaver: DrillInterleaver = DrillInterleaver(),
        selector: DesirableDifficultySelector = DesirableDifficultySelector(),
        startDifficulty: DrillDifficulty = .medium
    ) {
        self.queue = interleaver.order(mistakes)
        self.generator = generator
        self.grader = grader
        self.selector = selector
        self.difficulty = startDifficulty
        if let first = queue.first {
            self.current = generator.makeDrill(from: first, difficulty: startDifficulty)
        } else {
            self.isFinished = true
        }
    }

    public var successRate: Double {
        answered == 0 ? 0 : Double(correct) / Double(answered)
    }

    public var total: Int { queue.count }

    /// Grade a typed answer for the current item.
    @discardableResult
    public func submit(_ answer: String) -> DrillFeedback {
        guard let item = current else { return Self.noItemFeedback }
        return apply(grader.grade(answer: answer, for: item))
    }

    /// Move to the next item, regenerated at the (possibly adapted) difficulty.
    public func advance() {
        index += 1
        lastFeedback = nil
        if index < queue.count {
            current = generator.makeDrill(from: queue[index], difficulty: difficulty)
        } else {
            current = nil
            isFinished = true
        }
    }

    private func apply(_ grade: DrillGrade) -> DrillFeedback {
        answered += 1
        if grade == .correct { correct += 1 }
        difficulty = selector.next(current: difficulty, successRate: successRate)

        let mistake = queue[index]
        let feedback = DrillFeedback(
            grade: grade, correctAnswer: mistake.expected, explanation: mistake.explanation)
        lastFeedback = feedback
        return feedback
    }

    private static let noItemFeedback = DrillFeedback(grade: .incorrect, correctAnswer: "", explanation: "")
}
