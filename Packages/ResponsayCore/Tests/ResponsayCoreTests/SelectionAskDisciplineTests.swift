import Testing
import Foundation
@testable import ResponsayCore

// 298 — the live follow-up ask runs through SelectionAskSession (155):
// legal-scene selections keep the [待核] discipline on answers, general
// selections pass through untouched, and the selection context actually
// reaches coach.ask (it was silently wiped by reset() before this fix).

/// Records the context handed to `ask` — MockCoachAPI keeps no history.
private final class SpyCoachAPI: CoachAPI, @unchecked Sendable {
    var answer: ExpressionResult
    private(set) var askedContexts: [String] = []

    init(answer: ExpressionResult) { self.answer = answer }

    func express(_ intent: String, context: ExpressionContext?) async throws -> ExpressionResult {
        answer
    }
    func ask(_ question: String, context: String) async throws -> ExpressionResult {
        askedContexts.append(context)
        return answer
    }
    func analyze(_ sentence: String) async throws -> ProsodyAnalysis {
        ProsodyAnalysis(text: sentence, isGeneratedExample: false, sourceWord: nil,
                        ipa: "//", thoughtGroups: [], notes: nil)
    }
}

/// Selection text that classifies into a legal scene (same fixture as the 296
/// evaluateScene test — heading cues 起诉状/事实与理由).
private let legalSelection = "起诉状\n一、事实与理由\n被告拖欠货款，构成违约，应承担违约责任。"
private let generalSelection = "Could you help me polish this paragraph about my weekend trip?"

@MainActor
private func makeAskVM(question: String, coach: SpyCoachAPI) throws -> QuickCaptureViewModel {
    let speech = MockSpeechCaptureService(); speech.transcriptToReturn = question
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    return QuickCaptureViewModel(
        speech: speech, coach: coach, store: FileCaptureStore(fileURL: url),
        inserter: MockTextInserter(),
        legalRuntime: try LegalSkillRuntime.bundled(executor: nil))
}

@Test @MainActor func legalAsk_tagsNewCoordinates_inAnswerAndAlternatives() async throws {
    let coach = SpyCoachAPI(answer: ExpressionResult(
        idiomatic: "可主张违约责任，依据《民法典》第577条。",
        original: "对方违约怎么办",
        reasons: ["守约方可要求继续履行或赔偿损失"],
        alternatives: ["类案参照（2023）京01民终1234号判决。"]))
    let vm = try makeAskVM(question: "对方违约怎么办", coach: coach)

    await vm.prepareAskAndListen(context: legalSelection)
    #expect(vm.phase == .listening)
    #expect(vm.askSession?.mode == .legal)
    await vm.release()

    #expect(vm.phase == .review)
    // New coordinates in the answer carry the inline tag — on the main answer
    // and on alternatives (both insertable via activeIdiomatic).
    #expect(vm.result?.idiomatic.contains("《民法典》第577条[待核]") == true)
    #expect(vm.result?.alternatives.first?.contains("（2023）京01民终1234号[待核]") == true)
}

@Test @MainActor func generalAsk_leavesAnswerUntouched() async throws {
    let coach = SpyCoachAPI(answer: ExpressionResult(
        idiomatic: "依据《民法典》第577条。",   // coordinate-shaped, but general mode
        original: "q", reasons: []))
    let vm = try makeAskVM(question: "帮我看看这段", coach: coach)

    await vm.prepareAskAndListen(context: generalSelection)
    #expect(vm.askSession?.mode == .general)
    await vm.release()

    #expect(vm.phase == .review)
    #expect(vm.result?.idiomatic == "依据《民法典》第577条。")
    #expect(vm.result?.idiomatic.contains("[待核]") == false)
}

@Test @MainActor func askContext_reachesCoach_privacyTruncated() async throws {
    let coach = SpyCoachAPI(answer: ExpressionResult(idiomatic: "ok", original: "q", reasons: []))
    let vm = try makeAskVM(question: "这段说了什么", coach: coach)

    // Over-limit selection: the session truncates to the 169 default before the
    // context leaves the process.
    let long = String(repeating: "字", count: SelectionAskPolicy.defaultLimit + 50)
    await vm.prepareAskAndListen(context: long)
    await vm.release()

    #expect(coach.askedContexts.count == 1)
    #expect(coach.askedContexts.first?.isEmpty == false)   // was "" before 298 (reset() wiped it)
    #expect(coach.askedContexts.first?.count == SelectionAskPolicy.defaultLimit)
}

@Test @MainActor func askSession_recordsSingleBoundedTurn() async throws {
    let coach = SpyCoachAPI(answer: ExpressionResult(
        idiomatic: "可主张违约责任，依据《民法典》第577条。", original: "q", reasons: []))
    let vm = try makeAskVM(question: "对方违约怎么办", coach: coach)

    await vm.prepareAskAndListen(context: legalSelection)
    await vm.release()

    let session = try #require(vm.askSession)
    #expect(session.turns.count == 1)
    #expect(session.turns.first?.question == "对方违约怎么办")
    // The recorded answer is the disciplined (tagged) one.
    #expect(session.turns.first?.answer?.contains("[待核]") == true)
}

// Rubric 4 — no double-tagging when the disciplined answer later meets the 297
// insert-path ensureTags again (idempotency of the shared tagger).
@Test func askDiscipline_isIdempotent_withInsertPathEnsureTags() {
    let session = SelectionAskSession(rawSelection: "合同纠纷", mode: .legal)
    let once = QuickCaptureViewModel.applyAskDiscipline(
        ExpressionResult(idiomatic: "依据《民法典》第577条与（2023）京01民终1234号。",
                         original: "q", reasons: []),
        session: session)
    #expect(once.idiomatic.contains("《民法典》第577条[待核]"))

    // Second pass through the discipline → unchanged.
    let twice = QuickCaptureViewModel.applyAskDiscipline(once, session: session)
    #expect(twice.idiomatic == once.idiomatic)

    // And through the raw insert-path tagger (297) → still unchanged.
    let reinserted = VerificationPostProcessor().ensureTags(in: once.idiomatic, anchors: [])
    #expect(reinserted == once.idiomatic)
    #expect(!reinserted.contains("[待核][待核]"))
}
