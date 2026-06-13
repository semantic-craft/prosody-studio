import Foundation
import ResponsayCore

/// A read-aloud playback source (issue 198 refactor): bundles the three things the
/// `ReadAloudController` highlight loop needs — the word `timeline`, the current
/// `elapsed` clock, and the `isFinished` end-signal — behind one seam. The controller
/// picks a source (estimated vs real audio) instead of branching on a `usingRealAudio`
/// flag across `step` / `stop` / `pause`, collapsing the Divergent-Change smell.
@MainActor
protocol ReadAloudSource: AnyObject {
    var timeline: [TimedWord] { get }
    var elapsed: TimeInterval { get }
    var isFinished: Bool { get }
    /// Advance an internal clock by `dt` (scaled by `speed`). No-op when an external
    /// clock (the audio player) is authoritative.
    func advance(by dt: TimeInterval, speed: Double)
    /// Restart from the beginning (for 复读 looping).
    func reset()
    func pause()
    func resume()
    func stop()
}

/// Estimated-pace clock over a built timeline — no audio. Pure and headless-testable;
/// used as the immediate fallback and for 复读.
@MainActor
final class EstimatedReadAloudSource: ReadAloudSource {
    let timeline: [TimedWord]
    private(set) var elapsed: TimeInterval = 0
    private var paused = false

    init(timeline: [TimedWord]) { self.timeline = timeline }

    private var total: TimeInterval { ReadAloudTimeline.totalDuration(timeline) }
    var isFinished: Bool { elapsed >= total }

    func advance(by dt: TimeInterval, speed: Double) {
        guard !paused else { return }
        elapsed += dt * max(0.25, speed)
    }

    func reset() { elapsed = 0 }
    func pause() { paused = true }
    func resume() { paused = false }
    func stop() { elapsed = 0; paused = false }
}

/// The slice of `AudioReadAloudPlayer` a playback source needs — a seam (301) so
/// `PlayerReadAloudSource.reset()`'s re-schedule behavior is unit-testable with a
/// mock counting `play` calls. Streaming methods stay on the concrete player.
@MainActor
protocol ReadAloudAudioPlaying: AnyObject {
    var elapsed: TimeInterval { get }
    var isFinished: Bool { get }
    func play(_ composed: ComposedReadAloud) throws
    func pause()
    func resume()
    func stop()
}

/// Real-audio source: the `AVAudioPlayerNode` clock is authoritative, so `advance` is
/// a no-op and `elapsed`/`isFinished` come from the player. Used for composed
/// whole-utterance audio and for the streaming path (with an estimated-pace timeline,
/// since a live stream carries no per-word timing).
@MainActor
final class PlayerReadAloudSource: ReadAloudSource {
    let timeline: [TimedWord]
    private let player: any ReadAloudAudioPlaying
    /// Retained for 复读 looping (301): `reset()` re-schedules it from 0. nil on
    /// the streaming path — a finished live stream cannot be re-scheduled, so
    /// reset stays a no-op there (the loop then simply ends early).
    private let composed: ComposedReadAloud?

    init(
        timeline: [TimedWord],
        player: any ReadAloudAudioPlaying,
        composed: ComposedReadAloud? = nil
    ) {
        self.timeline = timeline
        self.player = player
        self.composed = composed
    }

    var elapsed: TimeInterval { player.elapsed }
    var isFinished: Bool { player.isFinished }

    func advance(by dt: TimeInterval, speed: Double) {}  // audio clock is authoritative
    /// 301: restart the real voice from the top (stop → schedule all chunks →
    /// play). Failure degrades to ending the loop early, never an infinite spin
    /// (the controller decrements `loopsRemaining` regardless).
    func reset() {
        guard let composed else { return }   // streaming: cannot restart
        try? player.play(composed)
    }
    func pause() { player.pause() }
    func resume() { player.resume() }
    func stop() { player.stop() }
}
