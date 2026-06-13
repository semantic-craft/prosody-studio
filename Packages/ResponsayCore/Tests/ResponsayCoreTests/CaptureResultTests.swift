import Foundation
import Testing
@testable import ResponsayCore

@Test func captureResult_roundTripsExpressFixture() throws {
    let result = CaptureResult(
        mode: .expressInEnglish,
        sourceTranscript: "我想礼貌地拒绝这个请求",
        insertText: "I'm afraid I won't be able to take this on.",
        outputLanguage: .english,
        transformKind: .intentToEnglish,
        insertPolicy: .insertImmediately,
        sidecarPolicy: .autoOpenCoach,
        coachCard: ExpressionResult(
            idiomatic: "I'm afraid I won't be able to take this on.",
            original: "我想礼貌地拒绝这个请求",
            reasons: ["把中文意图直接转成英文表达，不插入解释。"]))

    try result.validate()
    let data = try JSONEncoder().encode(result)
    let decoded = try JSONDecoder().decode(CaptureResult.self, from: data)
    #expect(decoded.mode == .expressInEnglish)
    #expect(decoded.insertText == "I'm afraid I won't be able to take this on.")
    #expect(decoded.sidecarPolicy == .autoOpenCoach)
    #expect(decoded.coachCard?.idiomatic == "I'm afraid I won't be able to take this on.")
}

@Test func captureResult_roundTripsPolishFixtureWithoutCoach() throws {
    let result = CaptureResult(
        mode: .polishSameLanguage,
        sourceTranscript: "这个观点还需要表述得更准确",
        insertText: "这个观点还需要表述得更准确。",
        outputLanguage: .source,
        transformKind: .sameLanguagePolish,
        insertPolicy: .insertImmediately,
        sidecarPolicy: .badgeOnly)

    try result.validate()
    #expect(result.coachCard == nil)
}

@Test func captureResult_insertModesRequireInsertText() throws {
    let result = CaptureResult(
        mode: .expressInEnglish,
        sourceTranscript: "我想拒绝",
        insertText: nil,
        outputLanguage: .english,
        transformKind: .intentToEnglish,
        insertPolicy: .insertImmediately,
        sidecarPolicy: .autoOpenCoach)

    #expect(throws: CaptureResultValidationError.missingInsertText(mode: .expressInEnglish)) {
        try result.validate()
    }
}

@Test func captureResult_learningModesAllowNilInsertText() throws {
    let result = CaptureResult(
        mode: .coach,
        sourceTranscript: "I need explain this better.",
        insertText: nil,
        outputLanguage: .englishWithChineseCoach,
        transformKind: .coachOnly,
        insertPolicy: .noInsert,
        sidecarPolicy: .autoOpenCoach)

    try result.validate()
}

@Test @MainActor func captureResultInserter_insertsOnlyInsertText() async throws {
    let inserter = MockTextInserter()
    let result = CaptureResult(
        mode: .expressInEnglish,
        sourceTranscript: "我想礼貌地拒绝",
        insertText: "I'm afraid I can't take this on.",
        outputLanguage: .english,
        transformKind: .intentToEnglish,
        insertPolicy: .insertImmediately,
        sidecarPolicy: .autoOpenCoach,
        coachCard: ExpressionResult(
            idiomatic: "COACH CARD SHOULD NOT BE INSERTED",
            original: "我想礼貌地拒绝",
            reasons: ["This explanation belongs in the sidecar."]))

    let didInsert = try await CaptureResultInserter.insertIfNeeded(result, using: inserter)

    #expect(didInsert)
    #expect(inserter.inserted == ["I'm afraid I can't take this on."])
}

@Test @MainActor func captureResultInserter_skipsNoInsertPolicies() async throws {
    let inserter = MockTextInserter()
    let result = CaptureResult(
        mode: .coach,
        sourceTranscript: "I need explain this better.",
        insertText: "This text must stay out of the target app.",
        outputLanguage: .englishWithChineseCoach,
        transformKind: .coachOnly,
        insertPolicy: .noInsert,
        sidecarPolicy: .autoOpenCoach)

    let didInsert = try await CaptureResultInserter.insertIfNeeded(result, using: inserter)

    #expect(!didInsert)
    #expect(inserter.inserted.isEmpty)
}
