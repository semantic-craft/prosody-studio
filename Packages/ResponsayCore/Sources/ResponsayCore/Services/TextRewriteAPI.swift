import Foundation

/// 重改写 (Heavy rewrite) — same-language restructure steered by a `RewriteTone`.
/// The heavier sibling of `TextPolishAPI`: `/polish` only tidies, `/rewrite` may
/// reorder/merge/upgrade wording while staying in the input's language. Reuses
/// `PolishResult` ({text, original, changes}); the chosen 改写风格 rides along as `tone`.
public protocol TextRewriteAPI: Sendable {
    /// 325: steered by a `RewriteStyle` — a built-in tone OR an imported/built-in
    /// StylePack (prompt + few-shot). The tone overload below bridges existing callers.
    func rewrite(_ text: String, style: RewriteStyle) async throws -> PolishResult
}

public extension TextRewriteAPI {
    /// Back-compat: every pre-325 call site passes a `RewriteTone`.
    func rewrite(_ text: String, tone: RewriteTone) async throws -> PolishResult {
        try await rewrite(text, style: .tone(tone))
    }
}
