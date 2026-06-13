import SwiftUI
import OSLog
import ResponsayCore

/// 136 + 194 + 197 — drives word highlight for 朗读 / 复读 on the stave.
///
/// The controller picks a `ReadAloudSource` (issue 198 refactor) and drives a single
/// highlight loop off it — no per-path branching on a `usingRealAudio` flag:
/// - 朗读 synthesizes real audio (194): `ReadAloudComposer` → per-sentence audio +
///   concatenated timeline, played by `AudioReadAloudPlayer` (a `PlayerReadAloudSource`).
/// - Streaming engines (197, Qwen realtime) play incrementally for low TTFB.
/// - On any synth failure it stays on the `EstimatedReadAloudSource` so the UI never
///   hard-fails. 复读 loops on the estimated clock (real-audio looping is a follow-up).
@MainActor
@Observable
final class ReadAloudController {
    enum Mode: Equatable { case idle, reading, repeating }

    private(set) var activeIndex: Int?
    private(set) var isPlaying = false
    private(set) var mode: Mode = .idle
    var speed: Double = 1.0

    /// The active playback source — its timeline/clock/end-signal drive the loop.
    private var source: (any ReadAloudSource)?
    private var loopsRemaining = 0
    private var task: Task<Void, Never>?
    private let tick: TimeInterval = 0.05

    private let player = AudioReadAloudPlayer()
    /// Injectable so tests can supply a stub/failing synthesizer; production uses
    /// the selected TTS engine.
    var makeSynthesizer: () throws -> any SpeechSynthesizer = {
        try TTSEngine.selected.makeSynthesizer()
    }
    /// Streaming factory (197), injectable for tests; nil = engine doesn't stream.
    var makeStreamingSynthesizer: () throws -> (any StreamingSpeechSynthesizer)? = {
        try TTSEngine.selected.makeStreamingSynthesizer()
    }
    /// 146 — fired once when a 朗读 playback reaches the end (not on manual stop).
    var onReadingFinished: (@MainActor () -> Void)?
    private let composer = ReadAloudComposer()
    private static let log = Logger(
        subsystem: "com.semanticcraft.responsay.mac", category: "ReadAloud")

    /// 朗读: play (with real audio when available), or pause if already reading.
    func toggleRead(_ analysis: ProsodyAnalysis) {
        if isPlaying { pause(); return }
        if mode == .reading, let source, !source.timeline.isEmpty {
            resume(); return   // resume after a pause
        }
        mode = .reading
        // Estimated source is the immediate fallback; real audio upgrades it.
        source = EstimatedReadAloudSource(timeline: ReadAloudTimeline.build(analysis))
        activeIndex = nil
        task?.cancel()
        task = Task { @MainActor [weak self] in
            await self?.startReading(analysis)
        }
    }

    /// 复读: loop the utterance `count` times — with real voice when the engine can
    /// synthesize (301; this was a silent highlight metronome before), estimated
    /// clock as the unchanged fallback. Streaming is deliberately NOT used here:
    /// looping needs re-schedulable buffers and a finished stream has none.
    func repeatRead(_ analysis: ProsodyAnalysis, count: Int = 3) {
        stop()
        mode = .repeating
        loopsRemaining = max(1, count)
        // Immediate fallback; the composed real voice upgrades it when ready.
        source = EstimatedReadAloudSource(timeline: ReadAloudTimeline.build(analysis))
        activeIndex = nil
        task = Task { @MainActor [weak self] in
            await self?.startRepeating(analysis)
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        source?.stop()
        source = nil
        isPlaying = false
        activeIndex = nil
        mode = .idle
        loopsRemaining = 0
    }

    // MARK: - Highlight stepping (testable seam)

    /// Set `activeIndex` for a given elapsed time over the active source's timeline.
    /// Returns `true` while still within the utterance, `false` once it reaches the end.
    @discardableResult
    func applyHighlight(at elapsed: TimeInterval) -> Bool {
        let timeline = source?.timeline ?? []
        activeIndex = ReadAloudTimeline.activeIndex(at: elapsed, in: timeline)
        return elapsed < ReadAloudTimeline.totalDuration(timeline)
    }

    // MARK: - Internals

    private func startReading(_ analysis: ProsodyAnalysis) async {
        // Synthesize off the main actor so the UI stays responsive; on any failure,
        // keep the already-set estimated source and play on the simulated clock.
        let engineTitle = TTSEngine.selected.title
        Diag.tts(.info, "朗读 start", fields: ["engine": engineTitle])
        do {
            // 197 — if the selected engine streams (Qwen realtime), play incrementally
            // for low TTFB.
            if let streamer = try makeStreamingSynthesizer() {
                try await startStreamingPlayback(analysis, streamer)
                return
            }
        } catch {
            Diag.tts(.error, "synth failed → estimated clock", fields: ["engine": engineTitle],
                     error: (error as? TTSError)?.userMessage ?? error.localizedDescription)
            Self.log.info("朗读 falling back to estimated clock: \(error.localizedDescription, privacy: .public)")
            guard !Task.isCancelled else { return }
            play()
            return
        }
        if let composed = await composeRealAudio(analysis), !Task.isCancelled,
           !composed.timeline.isEmpty {
            do {
                try player.play(composed)
                source = PlayerReadAloudSource(
                    timeline: composed.timeline, player: player, composed: composed)
                Diag.tts(.info, "synth done", fields: [
                    "engine": engineTitle,
                    "durationMs": String(Int(composed.totalDuration * 1000)),
                    "chunks": String(composed.chunks.count),
                ])
            } catch {
                Diag.tts(.error, "synth failed → estimated clock", fields: ["engine": engineTitle],
                         error: (error as? TTSError)?.userMessage ?? error.localizedDescription)
            }
        }
        guard !Task.isCancelled else { return }
        play()
    }

    /// 301 — real-voice 复读: compose once, then loop re-schedules the same
    /// buffers (`PlayerReadAloudSource.reset`). Synthesis failure keeps the
    /// estimated source already set by `repeatRead` — silent loop, never dead.
    private func startRepeating(_ analysis: ProsodyAnalysis) async {
        if let composed = await composeRealAudio(analysis), !Task.isCancelled,
           !composed.timeline.isEmpty,
           (try? player.play(composed)) != nil {
            source = PlayerReadAloudSource(
                timeline: composed.timeline, player: player, composed: composed)
            Diag.tts(.info, "复读 synth done", fields: [
                "durationMs": String(Int(composed.totalDuration * 1000)),
                "loops": String(loopsRemaining),
            ])
        }
        guard !Task.isCancelled else { return }
        play()
    }

    /// Shared non-streaming synthesis (朗读 + 复读). nil = fall back to the
    /// estimated clock; the failure is surfaced to diagnostics here.
    private func composeRealAudio(_ analysis: ProsodyAnalysis) async -> ComposedReadAloud? {
        let engineTitle = TTSEngine.selected.title
        do {
            let synth = try makeSynthesizer()
            let text = analysis.text
            let composer = self.composer
            let rate = speed
            return try await Task.detached(priority: .userInitiated) {
                try await composer.compose(text, using: synth, speed: rate)
            }.value
        } catch {
            // Surface the otherwise-silent failure into the diagnostics panel.
            Diag.tts(.error, "synth failed → estimated clock", fields: ["engine": engineTitle],
                     error: (error as? TTSError)?.userMessage ?? error.localizedDescription)
            Self.log.info("朗读/复读 falling back to estimated clock: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// 197 — incremental streaming playback: start the node, kick the loop, and feed
    /// chunks as they arrive (low TTFB). The audio clock decides when reading ends;
    /// highlight rides the estimated-pace timeline (a live stream has no word timing).
    private func startStreamingPlayback(
        _ analysis: ProsodyAnalysis, _ streamer: any StreamingSpeechSynthesizer
    ) async throws {
        try player.beginStreaming(sampleRate: Double(TTSAudio.defaultSampleRate))
        source = PlayerReadAloudSource(
            timeline: ReadAloudTimeline.build(analysis), player: player)
        activeIndex = nil
        play()
        Diag.tts(.info, "streaming begin", fields: ["engine": TTSEngine.selected.title])
        var chunkCount = 0
        let text = analysis.text
        let rate = speed
        do {
            for try await chunk in streamer.stream(text, speed: rate) {
                if Task.isCancelled { break }
                player.appendStreaming(chunk)
                chunkCount += 1
            }
            player.endStreaming()
            Diag.tts(.info, "streaming done", fields: ["chunks": String(chunkCount)])
        } catch {
            player.endStreaming()
            Diag.tts(.error, "streaming failed",
                     error: (error as? TTSError)?.userMessage ?? error.localizedDescription)
            throw error
        }
    }

    private func resume() {
        source?.resume()
        play()
    }

    private func pause() {
        task?.cancel(); task = nil
        source?.pause()
        isPlaying = false
    }

    private func play() {
        guard let source, !source.timeline.isEmpty else { return }
        isPlaying = true
        task?.cancel()
        task = Task { @MainActor [weak self] in
            while let self, self.isPlaying, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard self.isPlaying, !Task.isCancelled else { break }
                self.step()
            }
        }
    }

    private func step() {
        guard let source else { return }
        source.advance(by: tick, speed: speed)
        if source.isFinished {
            if mode == .repeating, loopsRemaining > 1 {
                loopsRemaining -= 1
                source.reset()
            } else {
                let wasReading = mode == .reading
                let callback = wasReading ? onReadingFinished : nil
                stop()
                callback?()
                return
            }
        }
        activeIndex = ReadAloudTimeline.activeIndex(at: source.elapsed, in: source.timeline)
    }
}
