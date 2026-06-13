import Testing
import Foundation
@testable import ResponsayCore

/// 105 — QuickCaptureViewModel `.legalSuggest` branch. Asserts the legal path
/// populates the palette WITHOUT inserting, and that legacy paths are untouched
/// (the rest of QuickCaptureViewModelTests / ReviewInsertFlowTests still pass).
@MainActor
private func makeLegalVM(
    context: ExpressionContext,
    withRuntime: Bool = true,
    executor: LegalSkillExecutorAPI? = nil,
    gate: CaptureGateDecision = .allowed,
    profile: LegalPracticeProfile? = nil,
    recorder: (@MainActor (LegalSkillRun) -> Void)? = nil
) throws -> (QuickCaptureViewModel, MockTextInserter) {
    let inserter = MockTextInserter()
    let store = FileCaptureStore(
        fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    let runtime = withRuntime ? try LegalSkillRuntime.bundled(executor: executor) : nil
    let vm = QuickCaptureViewModel(
        speech: MockSpeechCaptureService(),
        coach: MockCoachAPI(),
        store: store,
        inserter: inserter,
        contextProvider: { context },
        legalRuntime: runtime,
        legalProfileProvider: { profile },
        legalGateProvider: { gate },
        legalRunRecorder: recorder)
    return (vm, inserter)
}

/// A profile that opts into cloud (so non-sensitive selections skip the send-preview gate).
@MainActor private func cloudFirstProfile() -> LegalPracticeProfile {
    LegalPracticeProfile(id: "p", role: .practitioner, modelPreference: .cloudFirst,
                         createdAt: "t", updatedAt: "t")
}

/// A profile that keeps everything local.
@MainActor private func localFirstProfile() -> LegalPracticeProfile {
    LegalPracticeProfile(id: "p", role: .student, modelPreference: .localFirst,
                         createdAt: "t", updatedAt: "t")
}

@MainActor private final class RunCollector { var runs: [LegalSkillRun] = [] }

@Test @MainActor func legalBranch_populatesPalette_withoutInserting() async throws {
    let ctx = ExpressionContext(
        appName: "Microsoft Word",
        bundleIdentifier: "com.microsoft.word",
        windowTitle: "起诉状.docx",
        selectedText: "被告拖欠货款,构成违约。",
        textBeforeCursor: "一、事实与理由\n……")
    let (vm, inserter) = try makeLegalVM(context: ctx)

    await vm.processText("被告拖欠货款,构成违约。", outputMode: .legalSuggest)

    #expect(vm.phase == .review)
    #expect(vm.legalOutcome?.scene == .litigation)
    #expect(vm.legalCandidates.contains { $0.skillId == "practice.claim_and_defense.cn" })
    #expect(vm.legalCandidates.contains { $0.title == "请求权与抗辩分析" })
    #expect(inserter.inserted.isEmpty)           // legal palette NEVER inserts
    #expect(vm.result == nil)                     // not a coach result
}

@Test @MainActor func legalBranch_withoutRuntime_failsClearly() async throws {
    let (vm, inserter) = try makeLegalVM(context: ExpressionContext(selectedText: "x"), withRuntime: false)
    await vm.processText("x", outputMode: .legalSuggest)
    #expect(vm.phase == .error)
    #expect(vm.errorMessage?.isEmpty == false)
    #expect(inserter.inserted.isEmpty)
}

@Test @MainActor func selectLegalCandidate_withoutExecutor_failsClearlyNoInsert() async throws {
    // Runtime present but no executor wired → execute throws notConfigured, surfaced as
    // an error, never an insertion.
    let ctx = ExpressionContext(
        appName: "Microsoft Word", bundleIdentifier: "com.microsoft.word",
        windowTitle: "起诉状.docx", selectedText: "被告拖欠货款,构成违约。",
        textBeforeCursor: "一、事实与理由\n……")
    // cloudFirst → execute directly (skip the preview gate) → missing executor errors.
    let (vm, inserter) = try makeLegalVM(context: ctx, profile: cloudFirstProfile())
    await vm.processText("被告拖欠货款,构成违约。", outputMode: .legalSuggest)
    let card = try #require(vm.legalCandidates.first)

    await vm.selectLegalCandidate(card)

    #expect(inserter.inserted.isEmpty)
    #expect(vm.phase == .error)
}

@Test @MainActor func selectLegalCandidate_capturesResponse_withoutInserting() async throws {
    // cloudFirst + non-sensitive text → no send-preview gate → runs directly, captures the
    // structured response for the output view (107), never inserts.
    let mock = MockLegalExecutor(outputs: [legalGoodOutputJSON(summary: "已生成证据论证矩阵")])
    let ctx = ExpressionContext(
        appName: "Microsoft Word", bundleIdentifier: "com.microsoft.word",
        windowTitle: "起诉状.docx", selectedText: "被告拖欠货款,构成违约。",
        textBeforeCursor: "一、事实与理由\n……")
    let (vm, inserter) = try makeLegalVM(context: ctx, executor: mock, profile: cloudFirstProfile())
    await vm.processText("被告拖欠货款,构成违约。", outputMode: .legalSuggest)
    let card = try #require(vm.legalCandidates.first { $0.skillId == "practice.claim_and_defense.cn" })

    await vm.selectLegalCandidate(card)

    #expect(vm.legalSendConfirm == nil)           // non-sensitive cloudFirst → no confirm gate
    #expect(vm.legalResponse?.summary == "已生成证据论证矩阵")
    #expect(inserter.inserted.isEmpty)            // legal output is rendered (107), never inserted
}

@Test @MainActor func selectLegalCandidate_sensitive_showsSendPreviewBeforeAnyCloudCall() async throws {
    // 110 AC: sensitive text → send-preview, NOT an execute, until the user confirms.
    let mock = MockLegalExecutor(outputs: [legalGoodOutputJSON(summary: "已生成")])
    let ctx = ExpressionContext(
        appName: "Microsoft Word", bundleIdentifier: "com.microsoft.word",
        windowTitle: "代理词.docx", selectedText: "涉及客户保密信息，需主张违约责任。",
        textBeforeCursor: "一、事实与理由\n……")
    let (vm, inserter) = try makeLegalVM(context: ctx, executor: mock, profile: cloudFirstProfile())
    await vm.processText("涉及客户保密信息，需主张违约责任。", outputMode: .legalSuggest)
    let card = try #require(vm.legalCandidates.first)

    await vm.selectLegalCandidate(card)
    // gated: preview shown, nothing executed or inserted yet
    #expect(vm.legalSendConfirm?.requiresUserConfirm == true)
    #expect(vm.legalSendConfirm?.sendFields.contains(.selectedText) == true)
    #expect(vm.legalResponse == nil)
    #expect(await mock.calls.isEmpty)

    await vm.confirmLegalSend()
    #expect(vm.legalSendConfirm == nil)
    print("ERROR:", vm.errorMessage)
    #expect(vm.legalResponse?.summary == "已生成")
    #expect(inserter.inserted.isEmpty)
}

@Test @MainActor func cancelLegalSend_sendsNothing_returnsToPalette() async throws {
    let mock = MockLegalExecutor(outputs: [legalGoodOutputJSON()])
    let ctx = ExpressionContext(
        appName: "Microsoft Word", bundleIdentifier: "com.microsoft.word",
        windowTitle: "代理词.docx", selectedText: "涉及客户保密信息。",
        textBeforeCursor: "一、事实与理由\n……")
    let (vm, _) = try makeLegalVM(context: ctx, executor: mock, profile: cloudFirstProfile())
    await vm.processText("涉及客户保密信息。", outputMode: .legalSuggest)
    await vm.selectLegalCandidate(try #require(vm.legalCandidates.first))
    #expect(vm.legalSendConfirm != nil)

    vm.cancelLegalSend()
    #expect(vm.legalSendConfirm == nil)
    #expect(vm.legalResponse == nil)
    #expect(await mock.calls.isEmpty)             // nothing sent
}

@Test @MainActor func selectLegalCandidate_secureField_blockedNoPreviewNoCall() async throws {
    let mock = MockLegalExecutor(outputs: [legalGoodOutputJSON()])
    let ctx = ExpressionContext(
        appName: "Microsoft Word", bundleIdentifier: "com.microsoft.word",
        selectedText: "被告拖欠货款。", textBeforeCursor: "一、事实与理由\n……")
    let (vm, inserter) = try makeLegalVM(
        context: ctx, executor: mock, gate: .denied(.secureTextField), profile: cloudFirstProfile())
    await vm.processText("被告拖欠货款。", outputMode: .legalSuggest)
    await vm.selectLegalCandidate(try #require(vm.legalCandidates.first))

    #expect(vm.phase == .error)                   // blocked with a reason
    #expect(vm.legalSendConfirm == nil)
    #expect(vm.legalResponse == nil)
    #expect(await mock.calls.isEmpty)
    #expect(inserter.inserted.isEmpty)
}

@Test @MainActor func localFirstProfile_routesLocalOnly_noPreview() async throws {
    // 109 profile drives 110: localFirst → localOnly → runs directly (no cloud preview).
    let mock = MockLegalExecutor(outputs: [legalGoodOutputJSON(summary: "本地结果")])
    let ctx = ExpressionContext(
        appName: "Microsoft Word", bundleIdentifier: "com.microsoft.word",
        windowTitle: "起诉状.docx", selectedText: "被告拖欠货款,构成违约。",
        textBeforeCursor: "一、事实与理由\n……")
    let (vm, _) = try makeLegalVM(context: ctx, executor: mock, profile: localFirstProfile())
    await vm.processText("被告拖欠货款,构成违约。", outputMode: .legalSuggest)
    await vm.selectLegalCandidate(try #require(vm.legalCandidates.first))

    #expect(vm.legalSendConfirm == nil)                      // local → no cloud preview
    print("ERROR:", vm.errorMessage)
    #expect(vm.legalResponse?.summary == "本地结果")
    #expect(await mock.calls.first?.modelRoute == .localOnly) // privacy route forwarded
}

@Test @MainActor func execute_recordsRunAsHashNotRawText() async throws {
    let mock = MockLegalExecutor(outputs: [legalGoodOutputJSON()])
    let collector = RunCollector()
    let secret = "被告拖欠货款,构成违约。"
    let ctx = ExpressionContext(
        appName: "Microsoft Word", bundleIdentifier: "com.microsoft.word",
        windowTitle: "起诉状.docx", selectedText: secret,
        textBeforeCursor: "一、事实与理由\n……")
    let (vm, _) = try makeLegalVM(
        context: ctx, executor: mock, profile: cloudFirstProfile(),
        recorder: { collector.runs.append($0) })
    await vm.processText(secret, outputMode: .legalSuggest)
    let card = try #require(vm.legalCandidates.first { $0.skillId == "practice.claim_and_defense.cn" })

    await vm.selectLegalCandidate(card)

    let run = try #require(collector.runs.first)
    #expect(run.skillId == "practice.claim_and_defense.cn")
    #expect(run.scene == .litigation)
    #expect(run.modelRoute == .cloudAllowed)
    #expect(run.contextHash.hasPrefix("sha256:"))
    #expect(run.contextHash.contains(secret) == false)        // hash, never the raw text
}

@Test @MainActor func defaultAskEachTime_alwaysShowsSendPreview() async throws {
    // No profile → askEachTime default → every cloud legal call is gated by the preview (AC3).
    let mock = MockLegalExecutor(outputs: [legalGoodOutputJSON()])
    let ctx = ExpressionContext(
        appName: "Microsoft Word", bundleIdentifier: "com.microsoft.word",
        windowTitle: "起诉状.docx", selectedText: "被告拖欠货款,构成违约。",
        textBeforeCursor: "一、事实与理由\n……")
    let (vm, _) = try makeLegalVM(context: ctx, executor: mock)   // no profile
    await vm.processText("被告拖欠货款,构成违约。", outputMode: .legalSuggest)
    await vm.selectLegalCandidate(try #require(vm.legalCandidates.first))

    #expect(vm.legalSendConfirm != nil)
    #expect(vm.legalSendConfirm?.sendFields == [.selectedText, .sceneTag, .appCategory])
}

@Test @MainActor func selectLegalScene_reRoutesPaletteToChosenScene() async throws {
    // Ambiguous Word context → confirm card; confirming 学术 re-derives the academic palette.
    let ctx = ExpressionContext(
        appName: "Microsoft Word", bundleIdentifier: "com.microsoft.word",
        selectedText: "这段话需要看看。")
    let (vm, _) = try makeLegalVM(context: ctx)
    await vm.processText("这段话需要看看。", outputMode: .legalSuggest)
    #expect(vm.legalOutcome?.shouldConfirmScene == true)

    vm.selectLegalScene(.academicWriting)

    #expect(vm.legalOutcome?.scene == .academicWriting)
    #expect(vm.legalOutcome?.shouldConfirmScene == false)
    #expect(vm.legalCandidates.contains { $0.skillId == "research.search_strategy.cn" })
}

@Test @MainActor func evaluateScene_usesBrowserURLWhenSelectionSignalsAreInsufficient() throws {
    let vagueText = "这段材料需要核验一下。"
    let noURL = QuickCaptureViewModel(
        speech: MockSpeechCaptureService(),
        coach: MockCoachAPI(result: nil, error: nil),
        store: FileCaptureStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
        inserter: MockTextInserter(),
        contextProvider: { ExpressionContext(selectedText: nil) },
        legalRuntime: try LegalSkillRuntime.bundled(executor: nil))

    let degraded = try #require(noURL.evaluateScene(text: vagueText))
    #expect(degraded.scene == .unknown)

    let cnkiContext = ExpressionContext(
        selectedText: nil,
        browserURL: "https://kns.cnki.net/kcms/detail/secret-paper?query=private")
    #expect(cnkiContext.browserURLHost == "kns.cnki.net")
    #expect(cnkiContext.jsonObject.keys.contains("browserURLHost") == false)
    #expect(String(describing: cnkiContext.jsonObject).contains("secret-paper") == false)
    #expect(String(describing: cnkiContext.jsonObject).contains("private") == false)

    let withCNKI = QuickCaptureViewModel(
        speech: MockSpeechCaptureService(),
        coach: MockCoachAPI(result: nil, error: nil),
        store: FileCaptureStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
        inserter: MockTextInserter(),
        contextProvider: { cnkiContext },
        legalRuntime: try LegalSkillRuntime.bundled(executor: nil))

    let boosted = try #require(withCNKI.evaluateScene(text: vagueText))
    #expect(boosted.scene == .academicWriting)
    #expect(boosted.reasons.contains { $0.contains("网址 academicDatabase") })
    #expect(boosted.reasons.contains { $0.contains("secret-paper") } == false)
    #expect(boosted.reasons.contains { $0.contains("private") } == false)
}

@Test @MainActor func legalBranch_usesBrowserURLWhenSelectionSignalsAreInsufficient() async throws {
    let ctx = ExpressionContext(
        appName: "Google Chrome",
        bundleIdentifier: "com.google.Chrome",
        selectedText: nil,
        browserURL: "https://flk.npc.gov.cn/detail2.html?private=query")
    let (vm, inserter) = try makeLegalVM(context: ctx)

    await vm.processText("这段材料需要核验一下。", outputMode: .legalSuggest)

    #expect(vm.phase == .review)
    #expect(vm.legalOutcome?.scene == .litigation)
    #expect(vm.legalOutcome?.decision.classification.reasons.contains {
        $0.contains("网址 officialLawDatabase")
    } == true)
    #expect(vm.legalOutcome?.decision.classification.reasons.contains {
        $0.contains("private=query")
    } == false)
    #expect(inserter.inserted.isEmpty)
}

@Test @MainActor func legacyCoachPath_unaffectedByLegalAdditions() async throws {
    // Sanity: a normal coach capture still lands in review and inserts on confirm.
    let inserter = MockTextInserter()
    let speech = MockSpeechCaptureService(); speech.transcriptToReturn = "i want fix bug"
    let store = FileCaptureStore(
        fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    let vm = QuickCaptureViewModel(
        speech: speech,
        coach: MockCoachAPI(result: ExpressionResult(
            idiomatic: "I want to fix the bug.", original: "i want fix bug", reasons: ["缺 to"])),
        store: store, inserter: inserter)

    await vm.toggle(outputMode: .coachRewrite)   // start
    await vm.toggle(outputMode: .coachRewrite)   // stop + process

    #expect(vm.phase == .review)
    #expect(vm.legalCandidates.isEmpty)           // legal state stays empty on legacy paths
    #expect(vm.legalOutcome == nil)
}
