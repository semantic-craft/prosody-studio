import Testing
import Foundation
@testable import ResponsayCore

/// 166 — VerificationQueryRouter: query generation + per-source route dispatch (seam).
struct VerificationQueryRouterTests {
    private let router = VerificationQueryRouter()

    private func anchor(
        label: String = "《个保法》第24条",
        kind: VerificationKind = .law,
        query: String = "",
        sources: [VerificationSourcePreference] = []
    ) -> VerificationAnchor {
        VerificationAnchor(id: "a", label: label, kind: kind, query: query, preferredSources: sources)
    }

    // MARK: - Query generation

    @Test func query_usesSeededQueryElseLabel() {
        #expect(router.query(for: anchor(query: "个人信息保护法 第24条")) == "个人信息保护法 第24条")
        #expect(router.query(for: anchor(query: "")) == "《个保法》第24条")
    }

    // MARK: - Route dispatch

    @Test func baiduScholar_deepLinksToSearchPage() {
        let route = router.route(for: anchor(kind: .scholarlyArticle, query: "比例原则"), source: .baiduScholar)
        #expect(route.kind == .deepLink)
        #expect(route.url?.host == "xueshu.baidu.com")
        #expect(route.url?.query?.contains("wd=") == true)
    }

    @Test func cnki_deepLinksWithKeywordParam() {
        let route = router.route(for: anchor(), source: .cnki)
        #expect(route.kind == .deepLink)
        #expect(route.url?.host == "kns.cnki.net")
        #expect(route.url?.query?.contains("kw=") == true)
    }

    @Test func govLaw_opensSourceSite_noScrape() {
        let route = router.route(for: anchor(), source: .govLaw)
        #expect(route.kind == .deepLink)
        #expect(route.url?.host == "flk.npc.gov.cn")   // opens the source; query carried for paste
        #expect(route.query == "《个保法》第24条")
    }

    @Test func pkulaw_paywalled_opensOnly() {
        let route = router.route(for: anchor(kind: .caseLaw), source: .pkulaw)
        #expect(route.kind == .deepLink)
        #expect(route.url?.host == "www.pkulaw.com")    // paywalled → open only, never scrape
    }

    @Test func qwenSearch_isModelSearch_noURL() {
        let route = router.route(for: anchor(), source: .qwenSearch)
        #expect(route.kind == .modelSearch)
        #expect(route.url == nil)                        // backend search (Q3) — query only
    }

    @Test func manual_isCopyOnly() {
        let route = router.route(for: anchor(), source: .manual)
        #expect(route.kind == .copyOnly)
        #expect(route.url == nil)
    }

    // MARK: - Defaults + MCP seam

    @Test func defaultSource_byKind() {
        #expect(VerificationQueryRouter.defaultSource(for: .law) == .govLaw)
        #expect(VerificationQueryRouter.defaultSource(for: .caseLaw) == .pkulaw)
        #expect(VerificationQueryRouter.defaultSource(for: .scholarlyArticle) == .baiduScholar)
    }

    @Test func route_prefersAnchorPreferredSource() {
        let route = router.route(for: anchor(kind: .law, sources: [.cnki]))
        #expect(route.source == .cnki)                   // anchor preference beats the kind default
    }

    @Test func mcpRoute_reservesInterfaceOnly() {
        let route = router.mcpRoute(for: anchor())
        #expect(route.kind == .mcpSeam)                  // v0: reserved, not dispatched
        #expect(route.url == nil)
        #expect(route.query == "《个保法》第24条")
    }
}
