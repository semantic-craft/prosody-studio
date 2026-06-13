import Foundation

/// 137 — request for the **pure-rewrite** (改写) action: tone only, no teach flag.
public struct PolishQuietRequest: Codable, Sendable, Equatable {
    public let text: String
    public let tone: RewriteTone

    public init(text: String, tone: RewriteTone = .natural) {
        self.text = text
        self.tone = tone
    }
}

/// 137 — result of 改写: just the rewritten string, ready for one-tap replace.
///
/// No `why`, no `issues` — that absence is the *only* thing separating 改写
/// from 表达纠正 (`docs/specs/2026-06-07-polish-correct-read-actions.md` §1).
public struct PolishQuietResult: Decodable, Sendable, Equatable {
    public let rewritten: String

    public init(rewritten: String) {
        self.rewritten = rewritten
    }

    private enum CodingKeys: String, CodingKey { case rewritten, text }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let r = try c.decodeIfPresent(String.self, forKey: .rewritten) {
            rewritten = r
        } else {
            rewritten = try c.decode(String.self, forKey: .text)
        }
    }

    /// Parse the backend response, tolerating either a JSON object
    /// (`{"rewritten": …}` / `{"text": …}`) or a bare plain-text body.
    public static func parse(_ data: Data) -> PolishQuietResult {
        if let decoded = try? JSONDecoder().decode(PolishQuietResult.self, from: data) {
            return decoded
        }
        let raw = String(data: data, encoding: .utf8) ?? ""
        return PolishQuietResult(rewritten: raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public static func parse(_ string: String) -> PolishQuietResult {
        parse(Data(string.utf8))
    }
}
