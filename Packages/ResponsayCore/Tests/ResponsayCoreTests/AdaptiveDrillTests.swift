import Foundation
import Testing
@testable import ResponsayCore

// 071 — adaptive English drill engine: a MistakeRecord fed by the English coach,
// plus the desirable-difficulty selector (fluent methodology, ADR-0006). Drilling
// is English-only; the legal platform reuses the memory layer separately.

// MARK: - Model

@Test func mistakeRecord_codableRoundTrip() throws {
    let record = MistakeRecord(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        category: "语气",
        prompt: "你必须明天做完",
        expected: "Could you finish this by tomorrow?",
        explanation: "英语用疑问句更礼貌",
        drillPrompts: ["Could you …?"],
        createdAt: Date(timeIntervalSince1970: 100),
        sourceLanguage: "zh-CN")
    let decoded = try JSONDecoder().decode(
        MistakeRecord.self, from: try JSONEncoder().encode(record))
    #expect(decoded == record)
}

// MARK: - English extractor (connection to the coach)

@Test func englishExtractor_fromCorrectionResult_buildsRecord() {
    let result = ExpressionCorrectionResult(
        rewritten: "Could you finish this by tomorrow?",
        why: [WhyNote(kind: .tone, text: "原句过于生硬,英语用疑问句更礼貌"),
              WhyNote(kind: .perspective, text: "以对方为视角")],
        practice: ["Could you …?", "Would you mind …?"])

    let records = EnglishMistakeExtractor().extract(
        from: result, sourceText: "你必须明天做完")

    #expect(records.count == 1)
    let record = records[0]
    #expect(record.prompt == "你必须明天做完")
    #expect(record.expected == "Could you finish this by tomorrow?")
    #expect(record.category == "语气")                       // primary why kind title
    #expect(record.explanation.contains("更礼貌"))
    #expect(record.drillPrompts == ["Could you …?", "Would you mind …?"])
}

@Test func englishExtractor_fromCaptureItem_buildsRecord() throws {
    let item = CaptureItem(
        sourceText: "i want fix bug",
        language: "en-US",
        idiomatic: "I want to fix the bug.",
        reasons: ["Add 'to' before the verb."])

    let record = try #require(EnglishMistakeExtractor().extract(from: item).first)
    #expect(record.prompt == "i want fix bug")
    #expect(record.expected == "I want to fix the bug.")
    #expect(record.explanation.contains("Add 'to'"))
    #expect(record.sourceLanguage == "en-US")
}

@Test func englishExtractor_skipsWhenNoChange() {
    // No real mistake → nothing to drill.
    let same = ExpressionCorrectionResult(rewritten: "Hello.", practice: [])
    #expect(EnglishMistakeExtractor().extract(from: same, sourceText: "Hello.").isEmpty)
    let empty = ExpressionCorrectionResult(rewritten: "", practice: [])
    #expect(EnglishMistakeExtractor().extract(from: empty, sourceText: "x").isEmpty)
}

// MARK: - Desirable difficulty (fluent 60–80% target band)

@Test func difficultySelector_lowersWhenBelowTarget() {
    let selector = DesirableDifficultySelector()
    #expect(selector.next(current: .hard, successRate: 0.50) == .medium)
    #expect(selector.next(current: .easy, successRate: 0.30) == .easy)   // clamps
}

@Test func difficultySelector_raisesWhenAboveTarget() {
    let selector = DesirableDifficultySelector()
    #expect(selector.next(current: .easy, successRate: 0.90) == .medium)
    #expect(selector.next(current: .hard, successRate: 0.95) == .hard)   // clamps
}

@Test func difficultySelector_holdsInsideTargetBand() {
    let selector = DesirableDifficultySelector()
    #expect(selector.next(current: .medium, successRate: 0.65) == .medium)
    #expect(selector.next(current: .medium, successRate: 0.60) == .medium)
    #expect(selector.next(current: .medium, successRate: 0.80) == .medium)
}

// 303: follow-read feedback → drill record (the feedback card's two exits).
@Suite struct FollowReadMistakeBridgeTests {
    @Test func imperfectReadProducesDrillRecord() throws {
        let feedback = SpeechFeedback(
            targetText: "I would like to confirm the schedule.",
            recognizedText: "I would like confirm schedule.",
            similarity: 0.7, message: "漏读了 to / the")
        let record = try #require(MistakeRecord.followRead(from: feedback))
        #expect(record.category == "跟读")
        #expect(record.prompt == "I would like confirm schedule.")
        #expect(record.expected == "I would like to confirm the schedule.")
        #expect(record.explanation == "漏读了 to / the")
    }

    @Test func perfectOrEmptyReadProducesNothing() {
        let perfect = SpeechFeedback(
            targetText: "Hello there.", recognizedText: "hello there.",
            similarity: 1.0, message: "很好")
        #expect(MistakeRecord.followRead(from: perfect) == nil)
        let empty = SpeechFeedback(
            targetText: "  ", recognizedText: "", similarity: 0, message: "")
        #expect(MistakeRecord.followRead(from: empty) == nil)
    }

    @Test func silentReadKeepsTargetAsPrompt() throws {
        let silent = SpeechFeedback(
            targetText: "Good morning.", recognizedText: "",
            similarity: 0, message: "没有识别到语音")
        let record = try #require(MistakeRecord.followRead(from: silent))
        #expect(record.prompt == "Good morning.")
    }
}
