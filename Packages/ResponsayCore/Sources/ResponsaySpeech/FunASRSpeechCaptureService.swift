import AVFoundation
import AVFAudio
import Foundation
import OSLog
import ResponsayCore

@MainActor
public final class FunASRSpeechCaptureService: SpeechCaptureService {
    private let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "fun-asr")
    private let engine = AVAudioEngine()
    private let requireMicPermission: () throws -> Void
    private let bearerTokenProvider: () -> String
    private let modelProvider: () -> String
    private let vocabularyIDProvider: @Sendable () async -> String?
    private var run: FunASRCaptureRun?
    private var sink: RealtimeAudioSink?
    private var watchdog: AudioDeviceWatchdog?
    private var captureProfile: SpeechCaptureProfile = .dictation

    public private(set) var levels: AsyncStream<Float> = AsyncStream { _ in }
    public private(set) var partialTranscripts: AsyncStream<String> = AsyncStream { _ in }

    public init(
        requireMicPermission: @escaping () throws -> Void,
        bearerTokenProvider: @escaping () -> String,
        modelProvider: @escaping () -> String,
        vocabularyIDProvider: @escaping @Sendable () async -> String?
    ) {
        self.requireMicPermission = requireMicPermission
        self.bearerTokenProvider = bearerTokenProvider
        self.modelProvider = modelProvider
        self.vocabularyIDProvider = vocabularyIDProvider
    }

    public func start(locale: CaptureLocale) throws {
        try requireMicPermission()
        let token = bearerTokenProvider()
        guard !token.isEmpty else {
            throw CoachAPIError.message("Fun-ASR 实时语音识别缺少 API Key。请在「设置 › 听写 ASR」中配置通义千问密钥。")
        }

        let model = modelProvider()
        // No punctuation switch: the server ignores it and always punctuates
        // (live A/B 2026-06-11, issue 286) — faithful-profile users who need
        // unpunctuated raw text should use a different engine.
        let endpoint = FunASRRealtimeEndpoint(model: model)

        let (levelStream, levelContinuation) = AsyncStream.makeStream(of: Float.self)
        let (partialStream, partialContinuation) = AsyncStream.makeStream(of: String.self)
        levels = levelStream
        partialTranscripts = partialStream

        #if os(macOS)
        AudioInputDeviceSelector.apply(to: engine)
        #endif
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let (audioStream, audioContinuation) = AsyncStream.makeStream(of: AudioChunk.self)
        let sink = try RealtimeAudioSink(
            sourceFormat: format,
            audioContinuation: audioContinuation,
            levelContinuation: levelContinuation)
        let run = FunASRCaptureRun(
            endpoint: endpoint,
            bearerToken: token,
            vocabularyIDProvider: vocabularyIDProvider,
            audioStream: audioStream,
            partialContinuation: partialContinuation,
            log: log)
        run.start()

        // 288: mic-loss watchdog — Volcengine had detection-only, Fun-ASR had
        // neither; both now end the session with a typed error instead of
        // spinning silently (salvaging any already-captured text).
        let watchdog = AudioDeviceWatchdog(onTimeout: { [weak run, log] in
            log.error("Audio watchdog fired — mic lost; failing session (288)")
            run?.failDeviceLost(CoachAPIError.message(
                "麦克风似乎已断开（持续无音频）。请检查输入设备后重试。"))
        })
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
            watchdog.ping()
            sink.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            sink.finish()
            run.cancel()
            throw error
        }
        watchdog.start()
        self.watchdog = watchdog
        self.sink = sink
        self.run = run
        log.info("Fun-ASR started; model \(model, privacy: .public); locale \(locale.rawValue, privacy: .public)")
    }

    public func stop() async throws -> String {
        watchdog?.stop()
        watchdog = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        sink?.finish()
        sink = nil
        guard let run else { return "" }
        self.run = nil
        let text = try await run.finishAndWait()
        log.info("Fun-ASR stopped; transcript length \(text.count, privacy: .public)")
        return text
    }

}

extension FunASRSpeechCaptureService: SpeechCaptureProfileConfigurable {
    public func setCaptureProfile(_ profile: SpeechCaptureProfile) {
        captureProfile = profile
    }
}

extension FunASRSpeechCaptureService: SpeechPartialTranscriptProviding {}

// MARK: - Capture run

private final class FunASRCaptureRun: @unchecked Sendable {
    private let endpoint: FunASRRealtimeEndpoint
    private let bearerToken: String
    private let vocabularyIDProvider: @Sendable () async -> String?
    private let audioStream: AsyncStream<AudioChunk>
    private let partialContinuation: AsyncStream<String>.Continuation
    private let log: Logger
    private var driverTask: Task<Void, Never>?
    private var audioIterator: AsyncStream<AudioChunk>.AsyncIterator

    private let state = FunASRResultState()

    init(
        endpoint: FunASRRealtimeEndpoint,
        bearerToken: String,
        vocabularyIDProvider: @escaping @Sendable () async -> String?,
        audioStream: AsyncStream<AudioChunk>,
        partialContinuation: AsyncStream<String>.Continuation,
        log: Logger
    ) {
        self.endpoint = endpoint
        self.bearerToken = bearerToken
        self.vocabularyIDProvider = vocabularyIDProvider
        self.audioStream = audioStream
        self.audioIterator = audioStream.makeAsyncIterator()
        self.partialContinuation = partialContinuation
        self.log = log
    }

    func start() {
        driverTask = Task {
            do {
                try await runConnection()
                await state.finish()
            } catch {
                await state.fail(error)
            }
            partialContinuation.finish()
        }
    }

    private func runConnection() async throws {
        let session = URLSession.shared
        var request = URLRequest(url: endpoint.url)
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")

        let ws = session.webSocketTask(with: request)
        ws.resume()

        let taskID = UUID().uuidString
        let client = FunASRRealtimeClient(transport: ws, taskID: taskID)

        let vocabularyID = await vocabularyIDProvider()
        if let vocabularyID {
            log.info("Fun-ASR using hotword vocabulary \(vocabularyID, privacy: .public)")
        }
        try await client.sendRunTask(endpoint: endpoint, vocabularyID: vocabularyID)

        // Wait for task-started
        let started = try await client.receive()
        guard case .taskStarted = started else {
            if case let .taskFailed(_, message) = started {
                throw CoachAPIError.message("Fun-ASR 启动失败: \(message)")
            }
            throw CoachAPIError.message("Fun-ASR 未收到 task-started 响应")
        }

        try await withThrowingTaskGroup(of: RunOutcome.self) { group in
            group.addTask { try await self.sendLoop(client: client); return .sendDone }
            group.addTask { try await self.receiveLoop(client: client); return .receiveDone }
            while let outcome = try await group.next() {
                if outcome == .receiveDone {
                    group.cancelAll()
                    return
                }
            }
        }

        ws.cancel(with: .normalClosure, reason: nil)
    }

    private enum RunOutcome { case sendDone, receiveDone }

    private func sendLoop(client: FunASRRealtimeClient) async throws {
        while let chunk = await audioIterator.next() {
            try await client.sendAudio(chunk.pcm)
        }
        try await client.sendFinishTask()
    }

    private func receiveLoop(client: FunASRRealtimeClient) async throws {
        while !Task.isCancelled {
            let event = try await client.receive()
            if let update = await client.handleEvent(event) {
                switch update {
                case let .partial(preview):
                    await state.updatePreview(preview)
                    partialContinuation.yield(preview)
                case let .final(transcript):
                    await state.updateFinal(transcript)
                    partialContinuation.yield(transcript)
                case let .failed(message):
                    await state.fail(CoachAPIError.message(message ?? "Fun-ASR 识别失败"))
                    return
                }
            }
            if case .taskFinished = event { return }
        }
    }

    func finishAndWait() async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await self.state.wait() }
            group.addTask {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                throw CoachAPIError.message("Fun-ASR 等待最终结果超时。")
            }
            let result = try await group.next() ?? ""
            group.cancelAll()
            return result
        }
    }

    func cancel() {
        driverTask?.cancel()
        partialContinuation.finish()
    }

    /// 288: watchdog-detected mic loss. `FunASRResultState.fail` already does
    /// the graceful thing — salvages any captured text as the result, and only
    /// surfaces the typed error when nothing was heard at all.
    func failDeviceLost(_ error: Error) {
        let state = self.state
        Task { await state.fail(error) }
        driverTask?.cancel()
        partialContinuation.finish()
    }
}

private actor FunASRResultState {
    private var finalTranscript = ""
    private var lastPreview = ""
    private var finished = false
    private var failure: Error?
    private var waiters: [CheckedContinuation<String, Error>] = []

    func updatePreview(_ text: String) { lastPreview = text }

    func updateFinal(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        finalTranscript = TranscriptJoiner.join(finalTranscript, trimmed)
    }

    func finish() {
        finished = true
        resumeWaiters()
    }

    func fail(_ error: Error) {
        let trimmedPreview = lastPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalTranscript.isEmpty || !trimmedPreview.isEmpty {
            finalTranscript = TranscriptJoiner.join(finalTranscript, trimmedPreview)
            finished = true
        } else {
            failure = error
            finished = true
        }
        resumeWaiters()
    }

    func wait() async throws -> String {
        if let failure { throw failure }
        if finished { return finalTranscript }
        return try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func resumeWaiters() {
        let continuations = waiters
        waiters.removeAll()
        if let failure {
            for c in continuations { c.resume(throwing: failure) }
            return
        }
        let result = finalTranscript.isEmpty ? lastPreview : finalTranscript
        for c in continuations { c.resume(returning: result) }
    }
}
