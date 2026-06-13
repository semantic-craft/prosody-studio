import Foundation
import Testing
@testable import ResponsayCore

// 071 — turn a MistakeRecord into a presentable DrillItem. Difficulty drives
// how much help is shown (i+1 desirable difficulty: easy = more hint).

private func englishMistake() -> MistakeRecord {
    MistakeRecord(
        category: "语气", prompt: "你必须明天做完",
        expected: "Could you finish this by tomorrow?",
        explanation: "英语用疑问句更礼貌", drillPrompts: ["Could you …?"])
}

@Test func drillItem_codableRoundTrip() throws {
    let item = DrillItem(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        mistakeID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
        question: "Q", expectedAnswer: "A", hint: "H", difficulty: .medium)
    let decoded = try JSONDecoder().decode(DrillItem.self, from: try JSONEncoder().encode(item))
    #expect(decoded == item)
}

@Test func generator_productionDrillLinksAndCarriesAnswer() {
    let m = englishMistake()
    let item = TemplateDrillGenerator().makeDrill(from: m, difficulty: .medium)
    #expect(item.mistakeID == m.id)                          // links back to its mistake
    #expect(item.question.contains("你必须明天做完"))
    #expect(item.expectedAnswer == "Could you finish this by tomorrow?")
    #expect(item.difficulty == .medium)
}

@Test func generator_easyShowsHint_hardHidesIt() {
    let gen = TemplateDrillGenerator()
    #expect(gen.makeDrill(from: englishMistake(), difficulty: .easy).hint?.contains("更礼貌") == true)
    #expect(gen.makeDrill(from: englishMistake(), difficulty: .hard).hint == nil)
}
