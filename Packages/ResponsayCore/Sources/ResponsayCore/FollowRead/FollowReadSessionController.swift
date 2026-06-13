import Foundation
import Observation

/// 146 — platform-agnostic follow-read session state. UI layers drive reference playback
/// and recording; this type tracks phase transitions and holds the latest feedback.
@MainActor
@Observable
public final class FollowReadSessionController {
    public private(set) var phase: FollowReadPhase = .idle
    public private(set) var feedback: SpeechFeedback?
    public private(set) var targetText: String = ""

    public init() {}

    public func beginReferencePlayback(for analysis: ProsodyAnalysis) {
        targetText = analysis.text
        feedback = nil
        phase = .playingReference
    }

    public func referencePlaybackFinished() {
        guard phase == .playingReference else { return }
        phase = .recording
    }

    public func beginProcessing() {
        phase = .processing
    }

    /// Guarded against late async transcription (猎虫③ F2): a cancelled / sentence-
    /// switched session is `.idle` (or already re-playing) — the late result must
    /// not resurrect the feedback card or score against the wrong target.
    public func complete(with result: SpeechFeedback) {
        guard phase == .processing else { return }
        feedback = result
        phase = .feedback
    }

    public func fail(_ message: String) {
        guard phase == .processing || phase == .recording || phase == .playingReference else { return }
        feedback = nil
        phase = .failed(message)
    }

    public func retry() {
        feedback = nil
        phase = .idle
    }

    public func cancel() {
        feedback = nil
        targetText = ""
        phase = .idle
    }
}