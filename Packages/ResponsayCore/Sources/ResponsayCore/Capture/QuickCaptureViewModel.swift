import Foundation
import Observation

@MainActor
@Observable
public final class QuickCaptureViewModel {
    public internal(set) var phase: Phase = .idle
    public var locale: CaptureLocale = .english
    public internal(set) var transcript: String = ""
    public internal(set) var isFinalizingTranscript = false
    public internal(set) var result: ExpressionResult?
    public internal(set) var captureResult: CaptureResult?

    public internal(set) var legalCandidates: [LegalCandidateCard] = []
    public internal(set) var legalOutcome: LegalPaletteOutcome?
    public internal(set) var legalResponse: LegalSkillResponse?
    public internal(set) var legalResponseRoute: ModelRoute?
    public internal(set) var legalSendConfirm: LegalPrivacyDecision?
    public internal(set) var askSession: SelectionAskSession?

    public internal(set) var selectedAlternative: String?
    public internal(set) var didAutoInsertResult = false

    public var activeIdiomatic: String { selectedAlternative ?? result?.idiomatic ?? "" }

    public func selectAlternative(_ sentence: String) { selectedAlternative = (sentence == result?.idiomatic) ? nil : sentence }
    public func selectIdiomatic() { selectedAlternative = nil }

    public internal(set) var errorMessage: String?
    public internal(set) var level: Float = 0
    public internal(set) var recordingStartedAt: Date?

    let speech: SpeechCaptureService
    let coach: CoachAPI
    let textCoach: CoachAPI
    let store: CaptureStore
    let inserter: GatedTextInserter
    let contextProvider: (@MainActor () -> ExpressionContext?)?
    let streamingInsert: (@MainActor (_ transcript: String, _ mode: String, _ targetLanguage: String?) async -> StreamingTransformOutcome)?
    let streamingASRInsert: (@MainActor (_ deleteCount: Int, _ newText: String) -> Bool)?
    /// 375: owns the raw/polish/rewrite/translate/express transform decisions.
    let transformer: CaptureTransformer
    let legal: LegalCaptureCoordinator
    var pendingLegalCard: LegalCandidateCard?
    var levelTask: Task<Void, Never>?
    var partialTask: Task<Void, Never>?
    var errorDismissTask: Task<Void, Never>?
    var activeOutputMode: OutputMode = .coachRewrite
    var streamedPartialLength: Int = 0

    public init(
        speech: SpeechCaptureService,
        coach: CoachAPI,
        store: CaptureStore,
        inserter: TextInserter,
        textCoach: CoachAPI? = nil,
        polisher: (any TextPolishAPI)? = nil,
        translator: (any TextTranslationAPI)? = nil,
        rewriter: (any TextRewriteAPI)? = nil,
        contextProvider: (@MainActor () -> ExpressionContext?)? = nil,
        translationTargetProvider: (@MainActor () -> TranslationTargetLanguage)? = nil,
        rewriteToneProvider: (@MainActor () -> RewriteTone)? = nil,
        rewriteStyleProvider: (@MainActor () -> RewriteStyle)? = nil,
        streamingInsert: (@MainActor (_ transcript: String, _ mode: String, _ targetLanguage: String?) async -> StreamingTransformOutcome)? = nil,
        streamingASRInsert: (@MainActor (_ deleteCount: Int, _ newText: String) -> Bool)? = nil,
        legalRuntime: LegalSkillRuntime? = nil,
        legalProfileProvider: (@MainActor () -> LegalPracticeProfile?)? = nil,
        enabledLegalSkillsProvider: (@MainActor () -> Set<String>?)? = nil,
        legalGateProvider: (@MainActor () -> CaptureGateDecision)? = nil,
        legalRunRecorder: (@MainActor (LegalSkillRun) -> Void)? = nil
    ) {
        self.speech = speech
        self.coach = coach
        self.textCoach = textCoach ?? coach
        self.store = store
        self.inserter = GatedTextInserter(inserter)
        self.contextProvider = contextProvider
        self.streamingInsert = streamingInsert
        self.streamingASRInsert = streamingASRInsert
        self.transformer = CaptureTransformer(
            streamingInsert: streamingInsert,
            polisher: polisher,
            rewriter: rewriter,
            translator: translator,
            contextProvider: contextProvider,
            translationTargetProvider: translationTargetProvider,
            rewriteToneProvider: rewriteToneProvider,
            rewriteStyleProvider: rewriteStyleProvider)
        self.legal = LegalCaptureCoordinator(
            runtime: legalRuntime,
            contextProvider: contextProvider,
            profileProvider: legalProfileProvider,
            enabledProvider: enabledLegalSkillsProvider,
            gateProvider: legalGateProvider,
            runRecorder: legalRunRecorder)
    }

    public func toggle(outputMode: OutputMode = .coachRewrite) async {
        switch phase {
        case .listening: await stopAndProcess(outputMode: activeOutputMode)
        case .thinking:  return
        case .idle, .review, .error: startListening(outputMode: outputMode)
        }
    }

    public func push(outputMode: OutputMode = .coachRewrite) {
        if phase != .listening { startListening(outputMode: outputMode) }
    }

    public func release() async {
        if phase == .listening { await stopAndProcess(outputMode: activeOutputMode) }
    }

    public func confirmInsert() async {
        guard phase == .review, result != nil else { return }
        phase = .idle
        do {
            try await inserter.insert(activeIdiomatic)
        } catch {
            enterError(error.localizedDescription)
        }
    }

    public func discard() {
        guard phase == .review else { return }; reset(); phase = .idle
    }

    public func fail(_ message: String) {
        guard phase != .listening, phase != .thinking else { return }
        reset(); enterError(message)
    }

    #if DEBUG
    public func loadDesignReviewFixture() {
        reset(); transcript = "This conclusion feels not very stable."
        result = ExpressionResult(
            idiomatic: "I'm not sure that conclusion holds up.",
            original: transcript,
            reasons: [
                "“holds up” 更像英语里评价论证是否站得住的说法。",
                "“I'm not sure” 比直接否定更自然，适合学术讨论里的保留态度。"
            ],
            thinkingShift: "中文里常说“感觉不稳”；英语学术讨论更常把判断落到论证是否经得起检验。",
            alternatives: [
                "I don't think that conclusion is fully supported.",
                "That conclusion may need stronger evidence."
            ])
        phase = .review
    }

    public func loadCapsuleListeningFixture() {
        reset(); transcript = "今天我们测试 Qwen3-ASR 和 CLSCI"; level = 0.62
        recordingStartedAt = Date().addingTimeInterval(-8); phase = .listening
    }

    public func loadCapsuleFinalizingFixture() {
        reset(); transcript = "今天我们测试 Qwen3-ASR 和 CLSCI"; isFinalizingTranscript = true; phase = .thinking
    }

    public func loadCapsuleErrorFixture() { fail("当前是密码 / 安全输入框,已禁用语音输入。") }
    public func clearDesignFixture() { reset(); phase = .idle }
    #endif

    public func processText(_ text: String, outputMode: OutputMode = .coachRewrite) async {
        guard phase != .listening, phase != .thinking else { return }
        reset()
        phase = .thinking
        switch outputMode {
        case .rewriteSameLanguage:
            await rewriteAndInsert(text)
        case .translate:
            await translateAndInsert(text)
        case .translatePreview:
            await translateAndInsert(text, preview: true)
        case .legalSuggest:
            await processLegal(text)
        default:
            await processTranscript(text, using: textCoach)
        }
    }

    func startListening(outputMode: OutputMode) {
        reset()
        activeOutputMode = outputMode
        do {
            (speech as? SpeechCaptureProfileConfigurable)?
                .setCaptureProfile(outputMode.speechCaptureProfile)
            try speech.start(locale: locale)
            recordingStartedAt = Date()
            phase = .listening
            let stream = speech.levels
            levelTask = Task { [weak self] in
                for await v in stream { self?.level = v }
            }
            if let partials = (speech as? SpeechPartialTranscriptProviding)?.partialTranscripts {
                let streamsToHost = outputMode.streamsLiveTranscriptToHost
                partialTask = Task { [weak self] in
                    for await text in partials {
                        guard let self = self else { return }
                        self.transcript = text
                        if streamsToHost, let asrStreamer = self.streamingASRInsert {
                            let lengthToDelete = self.streamedPartialLength
                            if asrStreamer(lengthToDelete, text) {
                                self.streamedPartialLength = text.count
                            }
                        }
                    }
                }
            }
        } catch {
            enterError(error.localizedDescription)
        }
    }

    func stopAndProcess(outputMode: OutputMode) async {
        guard phase == .listening else { return }
        levelTask?.cancel(); levelTask = nil; level = 0
        phase = .thinking
        isFinalizingTranscript = true
        var partialCleanupFailed = false
        if streamedPartialLength > 0, let asrStreamer = streamingASRInsert {
            if asrStreamer(streamedPartialLength, "") {
                streamedPartialLength = 0
            } else {
                partialCleanupFailed = true
            }
        }
        do {
            let text = try await speech.stop()
            partialTask?.cancel(); partialTask = nil
            isFinalizingTranscript = false
            if partialCleanupFailed {
                reviewTranscriptAfterPartialCleanupFailure(text)
                return
            }
            switch outputMode {
            case .rawTranscript:
                await insertRawTranscript(text)
            case .polishedTranscript:
                await insertPolishedTranscript(text)
            case .rewriteSameLanguage:
                await rewriteAndInsert(text)
            case .coachRewrite:
                await processTranscript(text, using: coach)
            case .translate:
                await translateAndInsert(text)
            case .translatePreview:
                await translateAndInsert(text, preview: true)
            case .analysisFeedback:
                await processAnalysisFeedback(text)
            case .teachingFeedback:
                await processTeachingFeedback(text)
            case .practiceFeedback:
                await processPracticeFeedback(text)
            case .legalSuggest:
                await processLegal(text)
            case .askSelection:
                await processAskSelection(text)
            }
        } catch {
            partialTask?.cancel(); partialTask = nil
            isFinalizingTranscript = false
            transcript = ""
            enterError(CaptureFailure.classify(error).userMessage)
        }
    }

    func enterError(_ message: String) {
        errorMessage = message
        phase = .error
        errorDismissTask?.cancel()
        errorDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled, let self, self.phase == .error else { return }
            self.errorMessage = nil
            self.phase = .idle
        }
    }

    func reset() {
        errorMessage = nil; result = nil; captureResult = nil; selectedAlternative = nil; didAutoInsertResult = false; transcript = ""; isFinalizingTranscript = false; level = 0; recordingStartedAt = nil
        legalCandidates = []; legalOutcome = nil; legalResponse = nil; legalResponseRoute = nil
        legalSendConfirm = nil; pendingLegalCard = nil; askSession = nil
        inserter.beginSession()
        levelTask?.cancel(); levelTask = nil
        streamedPartialLength = 0
        partialTask?.cancel(); partialTask = nil
        errorDismissTask?.cancel(); errorDismissTask = nil
    }
}
