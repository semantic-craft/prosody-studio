import CryptoKit
import Foundation

/// The unit the adaptive drill engine consumes — one real English mistake the
/// user made, distilled into a drillable shape (ADR-0006: the personal mistake
/// stream is the curriculum; no fixed question bank). Drills practice English
/// only; the legal platform reuses the *memory* layer separately (see issue 071).
public struct MistakeRecord: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    /// Coarse bucket for interleaving (语气 / 视角 / 场景, or "表达").
    public let category: String
    /// The cue shown to the learner — the original 原话.
    public let prompt: String
    /// The idiomatic form to recall.
    public let expected: String
    /// Why the original wasn't idiomatic.
    public let explanation: String
    /// Ready-made practice cues from the coach (`practice[]`).
    public let drillPrompts: [String]
    public let createdAt: Date
    public let sourceLanguage: String?

    public init(
        id: UUID = UUID(),
        category: String,
        prompt: String,
        expected: String,
        explanation: String = "",
        drillPrompts: [String] = [],
        createdAt: Date = Date(),
        sourceLanguage: String? = nil
    ) {
        self.id = id
        self.category = category
        self.prompt = prompt
        self.expected = expected
        self.explanation = explanation
        self.drillPrompts = drillPrompts
        self.createdAt = createdAt
        self.sourceLanguage = sourceLanguage
    }
}

public extension MistakeRecord {
    /// Content-derived stable identity (305 verifier flag B): producers that
    /// re-extract the same mistake on every screen visit must hit the SAME row,
    /// so `SQLiteDrillStore.upsert`'s on-conflict branch (content-only update,
    /// SM-2 preserved) actually fires. A random UUID per extraction minted a
    /// fresh immediately-due row each time — the due() gate never held.
    static func contentID(category: String, prompt: String, expected: String) -> UUID {
        let digest = SHA256.hash(data: Data("\(category)\u{1F}\(prompt)\u{1F}\(expected)".utf8))
        var b = Array(digest.prefix(16))
        b[6] = (b[6] & 0x0F) | 0x50   // well-formed version/variant bits
        b[8] = (b[8] & 0x3F) | 0x80
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                           b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }

    /// 303: turn a follow-read result into a drillable record so the feedback
    /// card's「练错词 / 存入复习」exits feed the studio's SM-2 queue. A perfect
    /// read (recognized == target) is not a mistake and produces nothing —
    /// same rule as `EnglishMistakeExtractor`.
    static func followRead(from feedback: SpeechFeedback) -> MistakeRecord? {
        let target = feedback.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        let recognized = feedback.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, recognized.lowercased() != target.lowercased() else { return nil }
        let prompt = recognized.isEmpty ? target : recognized
        return MistakeRecord(
            id: contentID(category: "跟读", prompt: prompt, expected: target),
            category: "跟读",
            prompt: prompt,
            expected: target,
            explanation: feedback.message,
            drillPrompts: [],
            sourceLanguage: "en")
    }
}
