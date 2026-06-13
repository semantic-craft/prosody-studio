import Foundation

/// Where the English Coach runs — a per-capability choice (ADR-0026): the **cloud** coach
/// (default, Qwen) or the **offline** coach (on-machine Ollama). Opt-in offline; the default
/// stays cloud so nothing changes until the user deliberately switches. The raw value is the
/// wire token the backend's `selectCoachProvider` understands. Mirrors `CoachRegister`.
public enum CoachProvider: String, Codable, Sendable, Equatable, CaseIterable {
    case cloud
    case offline

    /// Chinese label for the coach-source picker.
    public var title: String {
        switch self {
        case .cloud:   return "云端"
        case .offline: return "离线本地"
        }
    }

    public var isOffline: Bool { self == .offline }

    /// Tolerant decode: an unknown value falls back to `.cloud` rather than failing.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CoachProvider(rawValue: raw.lowercased()) ?? .cloud
    }

    /// Resolve a stored provider string (e.g. a UserDefaults value) to a provider,
    /// defaulting to `.cloud` when missing or unrecognized. Pure so the default is
    /// unit-testable; the app's `CoachProviderSettings` wraps UserDefaults around it.
    public static func resolve(stored raw: String?) -> CoachProvider {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else { return .cloud }
        return CoachProvider(rawValue: raw) ?? .cloud
    }
}
