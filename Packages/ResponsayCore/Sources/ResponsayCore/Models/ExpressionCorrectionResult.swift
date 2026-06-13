import Foundation

/// 138 — request for the **rewrite + teach** (表达纠正) action.
public struct ExpressionCorrectionRequest: Codable, Sendable, Equatable {
    public let text: String
    public let tone: RewriteTone
    /// When `true`, ask for native-English expression rather than a minimal
    /// same-language polish (spec §1: "supports native-English expression").
    public let nativeExpression: Bool

    public init(text: String, tone: RewriteTone = .natural, nativeExpression: Bool = false) {
        self.text = text
        self.tone = tone
        self.nativeExpression = nativeExpression
    }
}

/// 138 — full 表达纠正 result: the rewrite, the flagged spans, the Chinese
/// "why" notes (语气/视角/场景, 2–5), and short practice prompts.
///
/// = 纯改写 (`rewritten`) + teaching payload
/// (`docs/specs/2026-06-07-polish-correct-read-actions.md` §1/§3).
public struct ExpressionCorrectionResult: Decodable, Sendable, Equatable {
    public let rewritten: String
    public let issues: [RewriteIssue]
    public let why: [WhyNote]
    public let practice: [String]

    /// Keep at most this many why-notes so the coach popup stays scannable
    /// (spec §3: 2–5 items).
    public static let maxWhy = 5

    public init(
        rewritten: String,
        issues: [RewriteIssue] = [],
        why: [WhyNote] = [],
        practice: [String] = []
    ) {
        self.rewritten = rewritten
        self.issues = issues
        self.why = Array(why.prefix(Self.maxWhy))
        self.practice = practice
    }

    private enum CodingKeys: String, CodingKey {
        case rewritten, text, issues, why, reasons, practice
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rewritten = try (c.decodeIfPresent(String.self, forKey: .rewritten))
            ?? (c.decode(String.self, forKey: .text))
        issues = (try c.decodeIfPresent([RewriteIssue].self, forKey: .issues)) ?? []
        // Prefer structured `why`; bridge the existing `/express` `reasons[]`
        // (plain strings) as 语气 notes so the two routes interoperate.
        let rawWhy: [WhyNote]
        if let structured = try c.decodeIfPresent([WhyNote].self, forKey: .why) {
            rawWhy = structured
        } else if let reasons = try c.decodeIfPresent([String].self, forKey: .reasons) {
            rawWhy = reasons.map { WhyNote(kind: .tone, text: $0) }
        } else {
            rawWhy = []
        }
        why = Array(rawWhy.prefix(Self.maxWhy))
        practice = (try c.decodeIfPresent([String].self, forKey: .practice)) ?? []
    }

    /// Return a copy whose issue spans are clamped into `original`, dropping any
    /// now-empty or inverted span (138: out-of-bounds span repair).
    public func repairingSpans(in original: String) -> ExpressionCorrectionResult {
        let length = original.count
        let repaired = issues.compactMap { issue -> RewriteIssue? in
            guard let span = issue.span.clamped(within: length) else { return nil }
            return RewriteIssue(span: span, label: issue.label, note: issue.note)
        }
        return ExpressionCorrectionResult(
            rewritten: rewritten, issues: repaired, why: why, practice: practice
        )
    }

    /// Drop the teaching payload → the pure-rewrite (改写) view of this result.
    public var asPolishQuiet: PolishQuietResult { PolishQuietResult(rewritten: rewritten) }
}
