import Foundation

/// Shared coach-provider routing for the backend text-action clients (/express, /polish,
/// /rewrite, /translate): attaches the coach `provider` (cloud | offline) + 离线 coach 模型档
/// (`tier`) to the request body, and picks the client timeout. The offline runner can take a
/// one-time cold model load (backend budget 300s), so the offline client timeout sits just
/// above it (330 > 300) — the same invariant the cloud path keeps (75 > backend 60) — so the
/// backend's response wins the race instead of a spurious client AbortSignal timeout.
public enum CoachRouting {
    public static let cloudTimeout: TimeInterval = 75
    public static let offlineTimeout: TimeInterval = 330

    /// Attach provider/tier to a string-valued JSON body. Provider rides whenever set; tier
    /// rides ONLY with the offline coach (it is meaningless to the cloud provider). The backend
    /// selects the offline runner model from the tier, ignoring the cloud route `model`.
    public static func apply(provider: CoachProvider?, tier: CoachTier?, to body: inout [String: String]) {
        if let provider { body["provider"] = provider.rawValue }
        if let tier, provider == .offline { body["tier"] = tier.rawValue }
    }

    public static func timeout(for provider: CoachProvider?) -> TimeInterval {
        provider == .offline ? offlineTimeout : cloudTimeout
    }
}
