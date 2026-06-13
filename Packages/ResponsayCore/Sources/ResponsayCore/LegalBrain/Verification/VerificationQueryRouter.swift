import Foundation

// MARK: - 166 Source-verification query routes (seam)
//
// Generates a verification query for a `[待核]` anchor and routes it to the matching
// source — 百度学术 / 知网 / 国家法规库 / 北大法宝 (deep-link to a SEARCH page only,
// never scraping paywalled content), the model built-in search (Qwen, Q3 seam), or a
// reserved MCP interface. The core produces the route descriptor; the macOS layer opens
// the URL / copies the query. Open Q6 (deep-link vs API vs MCP) stays a seam in v0.

public enum VerificationRouteKind: String, Sendable, Equatable {
    case deepLink      // open the source's search page (no content scraping)
    case modelSearch   // backend built-in search (Qwen) — query only, Q3 seam
    case mcpSeam       // reserved MCP interface — not dispatched in v0
    case copyOnly      // manual — copy the query, user searches
}

public struct VerificationRoute: Sendable, Equatable {
    public let kind: VerificationRouteKind
    public let source: VerificationSourcePreference
    public let query: String
    public let url: URL?               // present for `.deepLink`

    public init(kind: VerificationRouteKind, source: VerificationSourcePreference, query: String, url: URL?) {
        self.kind = kind
        self.source = source
        self.query = query
        self.url = url
    }
}

public struct VerificationQueryRouter: Sendable {
    public init() {}

    /// The verification query for an anchor (its seeded query, else its label).
    public func query(for anchor: VerificationAnchor) -> String {
        let q = anchor.query.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty ? anchor.label : q
    }

    /// Route an anchor to a source (explicit, else its preferred, else a kind default).
    public func route(for anchor: VerificationAnchor, source: VerificationSourcePreference? = nil) -> VerificationRoute {
        let resolved = source ?? anchor.preferredSources.first ?? Self.defaultSource(for: anchor.kind)
        let q = query(for: anchor)

        switch resolved {
        case .qwenSearch:
            // Backend built-in search (090 / Q3) — carry the query only, no URL.
            return VerificationRoute(kind: .modelSearch, source: resolved, query: q, url: nil)
        case .manual:
            return VerificationRoute(kind: .copyOnly, source: resolved, query: q, url: nil)
        case .baiduScholar, .cnki, .govLaw, .pkulaw, .webSearch,
             .itslaw, .wanfang, .vip, .rmfyalk:
            let endpoint = Self.endpoints[resolved]!
            let url = endpoint.param.flatMap { Self.search(endpoint.base, param: $0, query: q) }
                ?? URL(string: endpoint.base)   // paywalled / JS-search sites: open + paste query
            return VerificationRoute(kind: .deepLink, source: resolved, query: q, url: url)
        }
    }

    /// Reserved MCP interface (Open Q6): in v0 this only describes the call, it is not
    /// dispatched. A later phase wires an MCP verification provider behind this seam.
    public func mcpRoute(for anchor: VerificationAnchor) -> VerificationRoute {
        VerificationRoute(kind: .mcpSeam, source: .qwenSearch, query: query(for: anchor), url: nil)
    }

    /// The default source for an anchor kind when none is specified.
    public static func defaultSource(for kind: VerificationKind) -> VerificationSourcePreference {
        switch kind {
        case .scholarlyArticle:                 return .baiduScholar
        case .caseLaw:                          return .pkulaw
        case .law, .administrativeRule, .standard, .officialDocument:
            return .govLaw
        case .date, .money, .other:             return .baiduScholar
        }
    }

    // Public-search endpoints. `param` present → query goes in the URL; nil → the site
    // uses client-side / paywalled search, so we open it and the query is copied to paste
    // (never scraped).
    private static let endpoints: [VerificationSourcePreference: (base: String, param: String?)] = [
        .baiduScholar: ("https://xueshu.baidu.com/s", "wd"),
        .cnki: ("https://kns.cnki.net/kns8s/defaultresult/index", "kw"),
        .govLaw: ("https://flk.npc.gov.cn/", nil),     // 国家法律法规数据库（前端检索）
        .pkulaw: ("https://www.pkulaw.com/", nil),      // 北大法宝（付费，仅打开不抓取）
        .webSearch: ("https://www.baidu.com/s", "wd"),  // 通用搜索引擎兜底（百度网页）
        .itslaw: ("https://www.itslaw.com/search", "searchWord"),  // 无讼
        .wanfang: ("https://s.wanfangdata.com.cn/paper", "q"),     // 万方
        .vip: ("https://qikan.cqvip.com/Qikan/Search/Index", "key"), // 维普
        .rmfyalk: ("https://rmfyalk.court.gov.cn/", nil),  // 人民法院案例库（前端检索）
    ]

    private static func search(_ base: String, param: String, query: String) -> URL? {
        var components = URLComponents(string: base)
        components?.queryItems = [URLQueryItem(name: param, value: query)]
        return components?.url
    }
}
