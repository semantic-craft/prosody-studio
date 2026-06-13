import Foundation
import Testing
@testable import ResponsayCore

// 071 — the session loop: grade an answer, give immediate feedback, adapt
// difficulty, interleave categories, finish.

private func eng(_ prompt: String, _ expected: String, category: String = "语气") -> MistakeRecord {
    MistakeRecord(category: category, prompt: prompt, expected: expected, explanation: "更礼貌")
}

// MARK: Grader

@Test func grader_closedMatchIsLenientOnCasePunctSpace() {
    let item = DrillItem(mistakeID: UUID(), question: "q",
                         expectedAnswer: "Could you finish this by tomorrow?", difficulty: .medium)
    let g = DrillAnswerGrader()
    #expect(g.grade(answer: "could you finish this by tomorrow", for: item) == .correct)
    #expect(g.grade(answer: "you must finish tomorrow", for: item) == .incorrect)
}

// MARK: Interleaver

@Test func interleaver_avoidsAdjacentSameCategory() {
    let items = [eng("a", "A", category: "c1"),
                 eng("b", "B", category: "c1"),
                 eng("c", "C", category: "c2")]
    let ordered = DrillInterleaver().order(items)
    #expect(ordered.count == 3)
    for i in 1..<ordered.count {
        #expect(ordered[i].category != ordered[i - 1].category)
    }
}

// MARK: Session controller

@Test @MainActor func session_runsToFinishAndCountsCorrect() {
    let s = DrillSessionController(mistakes: [eng("你必须明天做完", "Could you finish this by tomorrow?")])
    #expect(s.current != nil)
    let fb = s.submit("could you finish this by tomorrow")
    #expect(fb.grade == .correct)
    #expect(s.correct == 1)
    #expect(s.answered == 1)
    s.advance()
    #expect(s.isFinished)
    #expect(s.current == nil)
}

@Test @MainActor func session_adaptsDifficultyFromSuccessRate() {
    let a = eng("p1", "alpha", category: "c1")
    let b = eng("p2", "beta", category: "c2")
    let s = DrillSessionController(mistakes: [a, b], startDifficulty: .medium)
    _ = s.submit("alpha")               // 1/1 = 100% → harder
    #expect(s.difficulty == .hard)
    s.advance()
    _ = s.submit("totally wrong")       // 1/2 = 50% → easier
    #expect(s.difficulty == .medium)
    s.advance()
    #expect(s.isFinished)
    #expect(s.successRate == 0.5)
}
