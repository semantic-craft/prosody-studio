import Testing
import Foundation
@testable import ResponsayCore

// 375 — the transform decisions (streaming-vs-API + CaptureResult/persistence
// intent) tested on the collaborator directly, without a view model.
@MainActor
private final class ThrowingPolish: TextPolishAPI {
    func polish(_ text: String) async throws -> PolishResult { throw CoachAPIError.message("no LLM") }
}

@MainActor
private func transformer(
    streamingInsert: (@MainActor (String, String, String?) async -> StreamingTransformOutcome)? = nil,
    polisher: (any TextPolishAPI)? = nil,
    rewriter: (any TextRewriteAPI)? = nil,
    translator: (any TextTranslationAPI)? = nil
) -> CaptureTransformer {
    CaptureTransformer(
        streamingInsert: streamingInsert,
        polisher: polisher, rewriter: rewriter, translator: translator,
        contextProvider: nil, translationTargetProvider: nil,
        rewriteToneProvider: nil, rewriteStyleProvider: nil)
}

// polish must degrade to the verbatim transcript when the LLM polish is
// unavailable — this is what makes "auto-punctuate by default" safe offline.
@Test @MainActor func transformer_polish_degradesToVerbatim_whenPolisherThrows() async {
    let outcome = await transformer(polisher: ThrowingPolish()).polish("今天没有模型", locale: .chinese)
    guard case let .insert(capture, item) = outcome else { Issue.record("expected .insert, got \(outcome)"); return }
    #expect(capture.insertText == "今天没有模型")
    #expect(item.idiomatic == "今天没有模型")
}

// when the streaming outlet writes the text itself, the transform is `.streamed`
// (host already has it; the VM just records state).
@Test @MainActor func transformer_polish_streamed_whenStreamingInsertStreams() async {
    let t = transformer(streamingInsert: { _, _, _ in .streamed(text: "已上屏") })
    let outcome = await t.polish("x", locale: .chinese)
    guard case let .streamed(capture, _) = outcome else { Issue.record("expected .streamed, got \(outcome)"); return }
    #expect(capture.insertText == "已上屏")
}

@Test @MainActor func transformer_rewrite_failsWhenNoRewriter() async {
    guard case let .failed(reason, _, _, _) = await transformer().rewrite("x", locale: .chinese) else {
        Issue.record("expected .failed"); return
    }
    #expect(reason.contains("Rewrite"))
}

@Test @MainActor func transformer_translate_failsWhenNoTranslator() async {
    guard case let .failed(reason, _, _, _) = await transformer().translate("x", preview: false, locale: .chinese) else {
        Issue.record("expected .failed"); return
    }
    #expect(reason.contains("Translation"))
}

// the coach path lands in review (no auto-insert) with the model's idiomatic result.
@Test @MainActor func transformer_express_landsInReview_fromCoach() async {
    let coach = MockCoachAPI(result: ExpressionResult(idiomatic: "I see.", original: "我懂了", reasons: ["更自然"]))
    let outcome = await transformer().express("我懂了", using: coach, locale: .chinese)
    guard case let .review(result, _, _) = outcome else { Issue.record("expected .review, got \(outcome)"); return }
    #expect(result.idiomatic == "I see.")
}

// a failed streaming transform with a non-empty partial persists it + carries the
// capture; an empty partial carries nothing (mirrors recordFailedStreamingTransform).
@Test @MainActor func transformer_polish_failedStreaming_keepsNonEmptyPartialOnly() async {
    let withText = transformer(streamingInsert: { _, _, _ in .failed(reason: "boom", insertedText: "半句") })
    guard case let .failed(_, capture, _, item) = await withText.polish("x", locale: .chinese) else {
        Issue.record("expected .failed"); return
    }
    #expect(capture?.insertText == "半句")
    #expect(item?.idiomatic == "半句")

    let empty = transformer(streamingInsert: { _, _, _ in .failed(reason: "boom", insertedText: "  ") })
    guard case let .failed(_, emptyCapture, _, emptyItem) = await empty.polish("x", locale: .chinese) else {
        Issue.record("expected .failed"); return
    }
    #expect(emptyCapture == nil)
    #expect(emptyItem == nil)
}

// MARK: - 375 feedback slice (analysis / practice / teaching)

// analysis keeps the user's sentence, lands in review with the analysis capture +
// prosody attached + the 分析模式 heading reason. (First direct test for this path.)
@Test @MainActor func transformer_analysisFeedback_landsInReview_withProsodyCapture() async {
    let coach = MockCoachAPI()
    let outcome = await transformer().analysisFeedback("This holds up.", using: coach, locale: .english)
    guard case let .review(result, capture, _) = outcome else { Issue.record("expected .review, got \(outcome)"); return }
    #expect(result.idiomatic == "This holds up.")
    #expect(result.reasons.first == "分析模式: 先看语音、重音、语调和连读。")
    #expect(capture.mode == .analysis)
    #expect(capture.prosodyAnalysis != nil)
}

// practice differs only in heading + capture mode (.practice).
@Test @MainActor func transformer_practiceFeedback_landsInReview_withPracticeCapture() async {
    let outcome = await transformer().practiceFeedback("Try again.", using: MockCoachAPI(), locale: .english)
    guard case let .review(result, capture, _) = outcome else { Issue.record("expected .review, got \(outcome)"); return }
    #expect(result.reasons.first == "练习模式: 保留你的句子,给出下一轮跟读目标。")
    #expect(capture.mode == .practice)
}

// analyze failure errors out (mirrors the former per-method catch — no review card).
@Test @MainActor func transformer_analysisFeedback_failsWhenAnalyzeThrows() async {
    let coach = MockCoachAPI(analyzeError: .message("offline"))
    guard case .failed = await transformer().analysisFeedback("x", using: coach, locale: .english) else {
        Issue.record("expected .failed"); return
    }
}

// teaching express, API path (no streaming outlet): express ok → `.expressed`, ready
// for the VM to insert + run teachingAnalyze.
@Test @MainActor func transformer_teachingExpress_apiPath_yieldsExpressed() async {
    let coach = MockCoachAPI(result: ExpressionResult(idiomatic: "Let me check.", original: "我看看", reasons: ["更口语"]))
    guard case let .expressed(idiomatic, exprReasons, capture) = await transformer().teachingExpress("我看看", using: coach, locale: .chinese) else {
        Issue.record("expected .expressed"); return
    }
    #expect(idiomatic == "Let me check.")
    #expect(exprReasons == ["更口语"])
    #expect(capture.insertText == "Let me check.")
}

// teaching express, express itself fails → `.failed` (nothing inserted).
@Test @MainActor func transformer_teachingExpress_failsWhenExpressThrows() async {
    let coach = MockCoachAPI(error: .message("backend down"))
    guard case .failed = await transformer().teachingExpress("我看看", using: coach, locale: .chinese) else {
        Issue.record("expected .failed"); return
    }
}

// teaching express, streaming outlet writes to host → `.streamed` (auto-inserted, no review).
@Test @MainActor func transformer_teachingExpress_streamed_whenStreamingInsertStreams() async {
    let t = transformer(streamingInsert: { _, _, _ in .streamed(text: "Let me check.") })
    guard case let .streamed(capture) = await t.teachingExpress("我看看", using: MockCoachAPI(), locale: .chinese) else {
        Issue.record("expected .streamed"); return
    }
    #expect(capture.insertText == "Let me check.")
}

// teaching express, streaming failed: non-empty partial carried; empty partial carries nothing.
@Test @MainActor func transformer_teachingExpress_streamedFailed_keepsNonEmptyPartialOnly() async {
    let withText = transformer(streamingInsert: { _, _, _ in .failed(reason: "boom", insertedText: "Let me") })
    guard case let .streamedFailed(_, capture, item) = await withText.teachingExpress("我看看", using: MockCoachAPI(), locale: .chinese) else {
        Issue.record("expected .streamedFailed"); return
    }
    #expect(capture?.insertText == "Let me")
    #expect(item?.idiomatic == "Let me")

    let empty = transformer(streamingInsert: { _, _, _ in .failed(reason: "boom", insertedText: "  ") })
    guard case let .streamedFailed(_, emptyCapture, emptyItem) = await empty.teachingExpress("我看看", using: MockCoachAPI(), locale: .chinese) else {
        Issue.record("expected .streamedFailed"); return
    }
    #expect(emptyCapture == nil)
    #expect(emptyItem == nil)
}

// teaching analyze success: prosody attached, teaching heading appended after expr reasons.
@Test @MainActor func transformer_teachingAnalyze_success_attachesProsody() async {
    let outcome = await transformer().teachingAnalyze(
        "我看看", idiomatic: "Let me check.", exprReasons: ["更口语"], using: MockCoachAPI(), locale: .chinese)
    guard case let .autoInsertedReview(result, capture, _) = outcome else { Issue.record("expected .autoInsertedReview"); return }
    #expect(result.idiomatic == "Let me check.")
    #expect(result.reasons.first == "更口语")
    #expect(result.reasons.contains { $0.hasPrefix("教学模式:") })
    #expect(capture.prosodyAnalysis != nil)
}

// teaching analyze failure: degrades to a needs-network note, prosody nil, still review.
@Test @MainActor func transformer_teachingAnalyze_analyzeFails_degradesWithNeedsNetworkNote() async {
    let coach = MockCoachAPI(analyzeError: .message("offline"))
    let outcome = await transformer().teachingAnalyze(
        "我看看", idiomatic: "Let me check.", exprReasons: ["更口语"], using: coach, locale: .chinese)
    guard case let .autoInsertedReview(result, capture, _) = outcome else { Issue.record("expected .autoInsertedReview"); return }
    #expect(result.reasons.contains { $0.contains("联网后看韵律") })
    #expect(capture.prosodyAnalysis == nil)
}
