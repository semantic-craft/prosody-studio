import Foundation

/// Server-side VAD configuration for a realtime session (`session.turn_detection`).
///
/// On the wire `type` is always `server_vad`; this models the tunable fields.
/// `threshold` ∈ [-1, 1] (lower = more sensitive), `silenceDurationMs` ∈
/// [200, 6000] (longer = tolerates in-sentence pauses, adds latency).
///
/// - Note: A `threshold` of `0.0` serialises to the JSON number `0` (both
///   `JSONSerialization` and `JSONEncoder` drop the fraction; JSON has no
///   int/float distinction, so `0` and `0.0` are the same value). The DashScope
///   server parses this field as a float, so `0` is accepted — confirmed against
///   the live DashScope socket in the 2026-06-06 device smoke.
public struct RealtimeTurnDetection: Sendable, Equatable {
    public let threshold: Double
    public let silenceDurationMs: Int

    public init(threshold: Double, silenceDurationMs: Int) {
        self.threshold = threshold
        self.silenceDurationMs = silenceDurationMs
    }
}

/// Dictation profiles from spec §4. Each maps to a VAD configuration; a `nil`
/// ``turnDetection`` selects Manual mode (client-controlled endpointing).
public enum RealtimeDictationProfile: String, Sendable, CaseIterable {
    case quickMessage
    case legalWriting
    case pushToTalk
    case command

    /// Volcengine server-side VAD tuning, or `nil` for profiles that use manual
    /// endpointing (pushToTalk uses `sendLastFrame()`; no server-side cut needed).
    public var volcengineVADConfig: VolcengineVADConfig? {
        switch self {
        case .quickMessage:
            return VolcengineVADConfig(endWindowSize: 400)
        case .legalWriting:
            return VolcengineVADConfig(endWindowSize: 800, forceToSpeechTime: 1000)
        case .command:
            return VolcengineVADConfig(endWindowSize: 300)
        case .pushToTalk:
            return nil
        }
    }

    /// VAD config for this profile, or `nil` for Manual mode (`pushToTalk`, `legalWriting`).
    public var turnDetection: RealtimeTurnDetection? {
        switch self {
        case .quickMessage:
            return RealtimeTurnDetection(threshold: 0.0, silenceDurationMs: 400)
        case .legalWriting:
            // Manual mode (no server VAD): the whole press→stop is ONE utterance,
            // so long in-sentence pauses never split a legal/academic sentence.
            // The client endpoints at stop (commit+finish); partials still stream.
            return nil
        case .command:
            return RealtimeTurnDetection(threshold: 0.0, silenceDurationMs: 400)
        case .pushToTalk:
            return nil
        }
    }
}
