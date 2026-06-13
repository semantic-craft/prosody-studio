import AVFoundation
import AVFAudio
import Foundation
import os
import OSLog
import ResponsayCore

/// App-resolved configuration for one Volcengine capture session. Resolved at `start()`
/// from the app's settings + Keychain (which stay app-side via `configProvider`), so this
/// package never reads `UserDefaults`/Keychain directly.
public struct VolcengineCaptureConfig: Sendable {
    public var credentials: VolcengineCredentials
    public var hotwords: [VolcengineHotword]
    public var boostingTableID: String?
    public var vadConfig: VolcengineVADConfig?

    public init(
        credentials: VolcengineCredentials,
        hotwords: [VolcengineHotword],
        boostingTableID: String?,
        vadConfig: VolcengineVADConfig?
    ) {
        self.credentials = credentials
        self.hotwords = hotwords
        self.boostingTableID = boostingTableID
        self.vadConfig = vadConfig
    }
}

/// Microphone → Volcengine 火山引擎 SAUC bigmodel **streaming** ASR. Same shape
/// as `FunASRSpeechCaptureService`: AVAudioEngine taps the mic, the shared
/// `RealtimeAudioSink` converts to 16 kHz/16-bit/mono PCM frames, and a driver
/// streams them to `VolcengineStreamingASRClient` (the ported openless protocol).
@MainActor
public final class VolcengineSpeechCaptureService: SpeechCaptureService {
    private let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "volc-asr")
    private let engine = AVAudioEngine()
    private let requireMicPermission: () throws -> Void
    private let configProvider: () throws -> VolcengineCaptureConfig
    private var run: VolcengineCaptureRun?
    private var sink: RealtimeAudioSink?
    private var watchdog: AudioDeviceWatchdog?
    private var configObserver: NSObjectProtocol?

    public private(set) var levels: AsyncStream<Float> = AsyncStream { _ in }
    public private(set) var partialTranscripts: AsyncStream<String> = AsyncStream { _ in }

    public init(
        requireMicPermission: @escaping () throws -> Void,
        configProvider: @escaping () throws -> VolcengineCaptureConfig
    ) {
        self.requireMicPermission = requireMicPermission
        self.configProvider = configProvider
    }

    public func start(locale: CaptureLocale) throws {
        try requireMicPermission()
        let config = try configProvider()
        let credentials = config.credentials
        let hotwords = config.hotwords
        let boostingTableID = config.boostingTableID
        let vadConfig = config.vadConfig

        let (levelStream, levelContinuation) = AsyncStream.makeStream(of: Float.self)
        let (partialStream, partialContinuation) = AsyncStream.makeStream(of: String.self)
        levels = levelStream
        partialTranscripts = partialStream

        #if os(macOS)
        AudioInputDeviceSelector.apply(to: engine)
        #endif
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let bridge = DeferredAudioBridge()
        let sink = try RealtimeAudioSink(
            sourceFormat: format,
            bridge: bridge,
            levelContinuation: levelContinuation)
        let client = VolcengineStreamingASRClient(
            credentials: credentials, hotwords: hotwords, boostingTableID: boostingTableID)
        let run = VolcengineCaptureRun(
            client: client,
            bridge: bridge,
            vadConfig: vadConfig,
            partialContinuation: partialContinuation,
            log: log)
        run.start()

        // 288: detection now acts — end the session with a typed error instead
        // of spinning silently while no audio flows.
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
            bridge.finish()
            run.cancel()
            throw error
        }
        watchdog.start()
        self.watchdog = watchdog
        self.configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [log] _ in
            log.warning("AVAudioEngine configuration changed — audio route may have shifted")
        }
        self.sink = sink
        self.run = run
        log.info("Volcengine streaming ASR started for \(locale.rawValue, privacy: .public); hotwords \(hotwords.count, privacy: .public); vad \(vadConfig.map { "endWindow=\($0.endWindowSize)" } ?? "none", privacy: .public)")
    }

    public func stop() async throws -> String {
        watchdog?.stop()
        watchdog = nil
        if let obs = configObserver { NotificationCenter.default.removeObserver(obs) }
        configObserver = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        sink?.finish()
        sink = nil
        guard let run else { return "" }
        self.run = nil
        run.finishBridge()
        let text = try await run.finishAndWait()
        log.info("Volcengine streaming ASR stopped; transcript length \(text.count, privacy: .public)")
        return text
    }
}

extension VolcengineSpeechCaptureService: SpeechPartialTranscriptProviding {}

/// Drives one streaming session: open → stream audio → end frame → await final.
/// Uses `DeferredAudioBridge` so audio capture begins immediately while the
/// WebSocket handshake runs in parallel — no audio lost during connection setup.
private final class VolcengineCaptureRun: @unchecked Sendable {
    private let client: VolcengineStreamingASRClient
    private let bridge: DeferredAudioBridge
    private let vadConfig: VolcengineVADConfig?
    private let partialContinuation: AsyncStream<String>.Continuation
    private let log: Logger
    private var driverTask: Task<String, Error>?
    private let continuationBox = ContinuationBox()

    init(
        client: VolcengineStreamingASRClient,
        bridge: DeferredAudioBridge,
        vadConfig: VolcengineVADConfig?,
        partialContinuation: AsyncStream<String>.Continuation,
        log: Logger
    ) {
        self.client = client
        self.bridge = bridge
        self.vadConfig = vadConfig
        self.partialContinuation = partialContinuation
        self.log = log
    }

    func start() {
        let client = self.client
        let bridge = self.bridge
        let vadConfig = self.vadConfig
        let partialContinuation = self.partialContinuation
        let log = self.log

        driverTask = Task<String, Error> {
            var finalText = ""
            var pendingAudio = Data()
            // Latency instrumentation (issue 055): capture start → first partial.
            let captureStart = Date()
            var isFirstSession = true

            while !Task.isCancelled {
                try await client.openSession(vadConfig: vadConfig)
                let sessionStart = Date()

                if !pendingAudio.isEmpty {
                    await client.consume(pcm: pendingAudio)
                }

                let (liveStream, liveCont) = AsyncStream.makeStream(of: AudioChunk.self)
                self.continuationBox.set(liveCont)
                let flushed = bridge.attach { chunk in liveCont.yield(chunk) }
                if !flushed.isEmpty {
                    log.info("bridge flushed \(flushed.count, privacy: .public) chunks (\(bridge.flushedByteCount, privacy: .public) bytes)")
                    for chunk in flushed {
                        pendingAudio.append(chunk.pcm)
                        if pendingAudio.count > 64_000 {
                            pendingAudio.removeFirst(pendingAudio.count - 64_000)
                        }
                        await client.consume(pcm: chunk.pcm)
                    }
                }

                let currentFinalText = finalText

                let shouldLogFirstPartial = isFirstSession
                isFirstSession = false
                let partialForward = Task {
                    var latencyLogged = !shouldLogFirstPartial
                    for await preview in client.partials {
                        if !latencyLogged {
                            latencyLogged = true
                            let ms = Int(Date().timeIntervalSince(captureStart) * 1000)
                            log.notice("first-partial-latency-ms: \(ms, privacy: .public) provider=volcengine")
                        }
                        let merged = TranscriptJoiner.crossSessionJoin(currentFinalText, preview)
                        partialContinuation.yield(merged)
                    }
                }

                var breakForReconnect = false
                for await chunk in liveStream {
                    pendingAudio.append(chunk.pcm)
                    if pendingAudio.count > 64_000 {
                        pendingAudio.removeFirst(pendingAudio.count - 64_000)
                    }

                    await client.consume(pcm: chunk.pcm)

                    if -sessionStart.timeIntervalSinceNow >= 58.0 {
                        breakForReconnect = true
                        break
                    }
                }

                try await client.sendLastFrame()
                let sessionText = try await client.awaitFinalResult()
                partialForward.cancel()

                finalText = TranscriptJoiner.crossSessionJoin(finalText, sessionText)

                if !breakForReconnect {
                    break
                }
            }
            partialContinuation.finish()
            return finalText
        }
    }

    // OSAllocatedUnfairLock: non-suspending, so usable from async finishAndWait
    // (NSLock.lock is unavailable in async contexts).
    private let deviceFailure = OSAllocatedUnfairLock<Error?>(initialState: nil)

    func finishBridge() {
        bridge.finish()
        continuationBox.finish()
    }

    func finishAndWait() async throws -> String {
        guard let driverTask else { return "" }
        do {
            return try await driverTask.value
        } catch {
            // 288: a watchdog-triggered teardown surfaces ITS typed error, not
            // the bare CancellationError the task cancellation produces.
            if let stored = deviceFailure.withLock({ $0 }) { throw stored }
            throw error
        }
    }

    /// 288: watchdog-detected mic loss — tear the session down NOW with a
    /// typed error so the capsule reports「麦克风断开」instead of spinning.
    func failDeviceLost(_ error: Error) {
        deviceFailure.withLock { if $0 == nil { $0 = error } }
        cancel()
    }

    func cancel() {
        finishBridge()
        driverTask?.cancel()
        partialContinuation.finish()
        let client = self.client
        Task { await client.cancel() }
    }
}

/// Thread-safe box for an `AsyncStream.Continuation` that can be set from an async
/// context and finished from a sync context (e.g. `finishBridge()`).
final class ContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<AudioChunk>.Continuation?

    func set(_ cont: AsyncStream<AudioChunk>.Continuation) {
        lock.lock()
        continuation = cont
        lock.unlock()
    }

    func finish() {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.finish()
    }
}
