import Foundation

/// 离线 coach 模型档 (offline coach model tier) — ADR-0026 §6. Only **E4B**
/// (Gemma 4 E4B, light/fast, public Ollama tag) remains; the heavy 12B tier was
/// dropped (non-public MLX build). The raw value is the wire token the backend maps
/// to an Ollama model tag (`offlineCoachTierTag`). Only meaningful when offline.
public enum CoachTier: String, Codable, Sendable, Equatable, CaseIterable {
    case e4b = "e4b"

    /// Chinese label for the tier picker.
    public var title: String {
        switch self {
        case .e4b: return "E4B · 轻快"
        }
    }

    /// One-line hint about the trade-off, for the picker subtitle.
    public var detail: String {
        switch self {
        case .e4b: return "更省内存、响应更快，适合多数 Mac（Gemma 4 E4B）"
        }
    }

    /// The Ollama model tag for this tier (mirrors backend `offlineCoachTierTag`), used by the
    /// App-direct local path that calls `localhost:11434` straight (Ollama-direct increment).
    public var ollamaTag: String {
        switch self {
        case .e4b: return "gemma4:e4b"
        }
    }

    /// Tolerant decode: an unknown value falls back to `.e4b` (the default tier).
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CoachTier(rawValue: raw.lowercased()) ?? .e4b
    }

    /// Resolve a stored tier string to a tier, defaulting to `.e4b` when missing or
    /// unrecognized. Pure so the default is unit-testable; `CoachTierSettings` wraps it.
    public static func resolve(stored raw: String?) -> CoachTier {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else { return .e4b }
        return CoachTier(rawValue: raw) ?? .e4b
    }
}
