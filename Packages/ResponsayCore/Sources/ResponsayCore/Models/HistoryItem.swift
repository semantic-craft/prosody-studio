import Foundation

/// Which text action produced a history entry. Mirrors the user-facing capture
/// modes (`QuickCaptureViewModel.OutputMode`) collapsed to the kinds worth
/// showing in History. Source: spec §6.2.2.
public enum TextActionKind: String, Codable, Sendable, Equatable, CaseIterable {
    case dictation   // 如实输入 — raw transcript
    case polish      // 改写原话 — light polish
    case rewrite     // 重改写 — heavy same-language rewrite
    case translate   // 翻译
    case coach       // 地道英文 + teaching
    case feedback    // 发音 / 口语反馈
    case other
}

/// Whether an entry was produced fully on-device or via a cloud provider — the
/// privacy posture recorded at capture time. Source: spec §6.2.2.
public enum RoutePrivacyMode: String, Codable, Sendable, Equatable, CaseIterable {
    case onDevice    // fully local (offline ASR/LLM/TTS)
    case cloud       // a cloud provider was used
    case unknown
}

/// One History entry: audio + text metadata for a past capture. Persisted by
/// `HistoryMediaStore`. Mirrors spec §6.2.2 — do NOT redesign the field set.
///
/// `audioFileURL` points at a file inside the store's `audioDirectory`; the
/// store persists only the filename and resolves the absolute URL on read.
public struct HistoryItem: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let createdAt: Date
    public let sourceAppName: String?
    public let sourceBundleID: String?
    public let actionKind: TextActionKind
    public let transcript: String?
    public let resultText: String?
    public let audioFileURL: URL?
    public let duration: TimeInterval?
    public let providerSummary: String?
    public let privacyMode: RoutePrivacyMode

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        sourceAppName: String? = nil,
        sourceBundleID: String? = nil,
        actionKind: TextActionKind,
        transcript: String? = nil,
        resultText: String? = nil,
        audioFileURL: URL? = nil,
        duration: TimeInterval? = nil,
        providerSummary: String? = nil,
        privacyMode: RoutePrivacyMode
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceAppName = sourceAppName
        self.sourceBundleID = sourceBundleID
        self.actionKind = actionKind
        self.transcript = transcript
        self.resultText = resultText
        self.audioFileURL = audioFileURL
        self.duration = duration
        self.providerSummary = providerSummary
        self.privacyMode = privacyMode
    }

    /// Best one-line text for a row: the produced result, falling back to the
    /// transcript.
    public var displayText: String {
        if let resultText, !resultText.isEmpty { return resultText }
        return transcript ?? ""
    }
}
