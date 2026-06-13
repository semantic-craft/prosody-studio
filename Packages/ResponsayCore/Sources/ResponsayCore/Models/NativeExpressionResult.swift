import Foundation

/// 140 — request for 中文意图 → 地道英文 (`expressInEnglish`). The input is a
/// Chinese *intent*, not English text to polish — which is what keeps it
/// distinct from pure 改写 (137).
public struct NativeExpressionRequest: Codable, Sendable, Equatable {
    public let intent: String
    public let tone: RewriteTone

    public init(intent: String, tone: RewriteTone = .natural) {
        self.intent = intent
        self.tone = tone
    }
}

/// 140 — idiomatic English + Chinese coaching. Carries `why` (speech act /
/// register / perspective) + alternatives — it is a **teaching** action and is
/// never collapsed to the rewrite-only shape of 137 (`PolishQuietResult`).
public struct NativeExpressionResult: Decodable, Sendable, Equatable {
    public let english: String
    public let why: [WhyNote]
    public let alternatives: [String]

    public init(english: String, why: [WhyNote] = [], alternatives: [String] = []) {
        self.english = english
        self.why = why
        self.alternatives = alternatives
    }

    private enum CodingKeys: String, CodingKey {
        case english, idiomatic, why, reasons, alternatives
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        english = try (c.decodeIfPresent(String.self, forKey: .english))
            ?? (c.decode(String.self, forKey: .idiomatic))
        if let structured = try c.decodeIfPresent([WhyNote].self, forKey: .why) {
            why = structured
        } else if let reasons = try c.decodeIfPresent([String].self, forKey: .reasons) {
            // Bridge the existing /express `reasons[]` as speech-act (语气) notes.
            why = reasons.map { WhyNote(kind: .tone, text: $0) }
        } else {
            why = []
        }
        alternatives = try c.decodeIfPresent([String].self, forKey: .alternatives) ?? []
    }
}
