import Foundation

// MARK: - SearchVerificationService
//
// Orchestrates LLM-powered online verification for [待核] anchors. Builds a
// verification prompt, delegates to the LLM (with web search enabled via
// LLMSearchControl), parses the result (via LLMSearchResultParser), and maps
// to VerifiedSource. Core-only (no UI, no HTTP); the executor and HTTP layer
// are injected by the macOS app.
//
// Critical constraint: 搜不到 ≠ 不存在. This service NEVER sets status to
// .rejected. When search returns nil, the anchor stays .pending.

public enum SearchVerificationService {

    // MARK: - Prompt construction

    /// Builds a verification prompt for the given query. The prompt instructs
    /// the LLM to search and return structured information, or clearly state
    /// "未找到" if nothing was found. It must never fabricate results.
    public static func buildVerificationPrompt(
        query: String,
        kind: VerificationKind? = nil
    ) -> String {
        let kindHint: String
        switch kind {
        case .caseLaw:
            kindHint = "这是一个案号/案件引用。请搜索该案件的案由、当事人、裁判日期和裁判结果。"
        case .scholarlyArticle:
            kindHint = "这是一个学术文献/论文引用。请搜索确认该文献是否真实存在，返回期刊名称、卷期、页码和作者。"
        case .law, .administrativeRule, .officialDocument:
            kindHint = "这是一个法律法规/规范性文件引用。请搜索该条文的原文全文。"
        case .standard:
            kindHint = "这是一个行业标准编号。请搜索该标准的名称、发布日期和发布机构。"
        default:
            kindHint = "请搜索以下引用的相关信息。"
        }

        return """
        请使用联网搜索功能，核验以下法律引用的真实性。

        \(kindHint)

        查询：\(query)

        要求：
        1. 请返回你搜索到的原文或摘要，以及来源网址。
        2. 如果搜索不到相关内容，请明确说明"未找到相关结果"，不要编造任何信息。
        3. 如果搜索结果不确定或可能有误，请说明不确定性。
        """
    }

    // MARK: - Result mapping

    /// Convert a parser result to the domain `VerifiedSource`.
    public static func toVerifiedSource(_ result: LLMSearchResultParser.SearchResult) -> VerifiedSource {
        VerifiedSource(
            title: result.title,
            url: result.url,
            accessedAt: ISO8601DateFormatter().string(from: Date()),
            provider: result.provider,
            snippet: result.snippet)
    }

    // MARK: - Search capability check (delegates to LLMSearchControl)

    public static func supportsSearch(providerId: String, baseURLHost: String) -> Bool {
        LLMSearchControl.supportsSourceResults(providerId: providerId, baseURLHost: baseURLHost)
    }

    // MARK: - Anchor status update

    /// Apply a verification result to an anchor. nil = not found → stays .pending.
    /// Never sets .rejected — 搜不到 ≠ 不存在.
    public static func applyResult(_ source: VerifiedSource?, to anchor: inout VerificationAnchor) {
        guard let source else { return }
        anchor.source = source
        switch anchor.kind {
        case .law, .administrativeRule, .officialDocument, .standard:
            anchor.status = .verifiedLaw
        case .caseLaw:
            anchor.status = .verifiedCase
        case .scholarlyArticle:
            anchor.status = .scholarlyReference
        case .date, .money, .other:
            anchor.status = .userConfirmed
        }
    }
}
