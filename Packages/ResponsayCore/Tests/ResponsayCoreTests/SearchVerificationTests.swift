import Testing
import Foundation
@testable import ResponsayCore

// MARK: - SearchVerificationService integration tests

/// Mock executor that records calls and returns canned search responses.
private final class MockSearchExecutor: LegalSkillExecutorAPI, @unchecked Sendable {
    var searchCalls: [(anchor: VerificationAnchor, route: ModelRoute)] = []
    var searchResponse: VerifiedSource?
    var shouldThrow = false

    func executeSkill(_ request: LegalSkillExecutionRequest) async throws -> LegalSkillExecutionResponse {
        throw LegalSkillRuntimeError.executorNotImplemented(skillId: "unused")
    }

    func supportsSearchVerification(route: ModelRoute) -> Bool {
        !shouldThrow && route == .cloudAllowed
    }

    func searchVerification(_ anchor: VerificationAnchor, route: ModelRoute) async throws -> VerifiedSource? {
        searchCalls.append((anchor, route))
        if shouldThrow { throw LegalSkillRuntimeError.executorNotImplemented(skillId: "search") }
        return searchResponse
    }
}

@Suite("SearchVerificationService — LLM-powered verification")
struct SearchVerificationTests {

    // MARK: - Prompt construction

    @Test func buildPrompt_containsQueryAndNonFabricationInstruction() {
        let prompt = SearchVerificationService.buildVerificationPrompt(query: "《民法典》第577条")
        #expect(prompt.contains("《民法典》第577条"))
        #expect(prompt.contains("不要编造") || prompt.contains("不得编造"))
        #expect(prompt.contains("未找到") || prompt.contains("搜索不到"))
    }

    @Test func buildPrompt_forCaseNumber_containsCaseHints() {
        let prompt = SearchVerificationService.buildVerificationPrompt(
            query: "(2019)最高法民再59号", kind: .caseLaw)
        #expect(prompt.contains("案号") || prompt.contains("案件"))
    }

    @Test func buildPrompt_forPaper_containsScholarlyHints() {
        let prompt = SearchVerificationService.buildVerificationPrompt(
            query: "王利明 人工智能时代的侵权责任 法学研究", kind: .scholarlyArticle)
        #expect(prompt.contains("文献") || prompt.contains("论文") || prompt.contains("期刊"))
    }

    // MARK: - Result mapping to VerifiedSource

    @Test func parseToVerifiedSource_mapsFieldsCorrectly() throws {
        let searchResult = LLMSearchResultParser.SearchResult(
            title: "民法典第577条",
            url: "https://flk.npc.gov.cn/detail2.html?id=abc",
            snippet: "第五百七十七条　当事人一方不履行合同义务...",
            provider: "kimi")
        let source = SearchVerificationService.toVerifiedSource(searchResult)
        #expect(source.title == "民法典第577条")
        #expect(source.url == "https://flk.npc.gov.cn/detail2.html?id=abc")
        #expect(source.snippet == "第五百七十七条　当事人一方不履行合同义务...")
        #expect(source.provider == "kimi")
        #expect(!source.accessedAt.isEmpty)
    }

    // MARK: - supportsSearch check

    @Test func supportsSearch_trueForKimi() {
        #expect(SearchVerificationService.supportsSearch(providerId: "kimi", baseURLHost: "api.moonshot.cn"))
    }

    @Test func supportsSearch_trueForQwenDashScopeNativeSourceResults() {
        #expect(SearchVerificationService.supportsSearch(providerId: "qwen", baseURLHost: "dashscope.aliyuncs.com"))
    }

    @Test func supportsSearch_falseForQwenTokenPlanWithoutSourceResults() {
        #expect(!SearchVerificationService.supportsSearch(
            providerId: "qwen-token-plan",
            baseURLHost: "token-plan.cn-beijing.maas.aliyuncs.com"))
    }

    @Test func supportsSearch_falseForDeepSeek() {
        #expect(!SearchVerificationService.supportsSearch(providerId: "deepseek", baseURLHost: "api.deepseek.com"))
    }

    // MARK: - Anchor status discipline

    @Test func nilResult_neverSetsRejected() {
        var anchor = VerificationAnchor(
            id: "test:1", label: "测试", kind: .law, status: .pending, query: "测试")
        SearchVerificationService.applyResult(nil, to: &anchor)
        #expect(anchor.status == .pending)
        #expect(anchor.source == nil)
    }

    @Test func successResult_setsVerifiedLaw() {
        var anchor = VerificationAnchor(
            id: "test:1", label: "《民法典》第577条", kind: .law, status: .pending, query: "民法典577")
        let source = VerifiedSource(
            title: "民法典", url: "https://flk.npc.gov.cn", accessedAt: "2026-06-11", provider: "kimi")
        SearchVerificationService.applyResult(source, to: &anchor)
        #expect(anchor.status == .verifiedLaw)
        #expect(anchor.source?.provider == "kimi")
    }

    @Test func successResult_caseLaw_setsVerifiedCase() {
        var anchor = VerificationAnchor(
            id: "test:2", label: "(2019)最高法民再59号", kind: .caseLaw, status: .pending, query: "案号")
        let source = VerifiedSource(
            title: "判决书", url: "https://itslaw.com/detail", accessedAt: "2026-06-11", provider: "qwen")
        SearchVerificationService.applyResult(source, to: &anchor)
        #expect(anchor.status == .verifiedCase)
    }

    @Test func successResult_paper_setsScholarlyReference() {
        var anchor = VerificationAnchor(
            id: "test:3", label: "王利明 侵权责任", kind: .scholarlyArticle, status: .pending, query: "论文")
        let source = VerifiedSource(
            title: "论文", url: "https://cnki.net/article", accessedAt: "2026-06-11", provider: "zhipu")
        SearchVerificationService.applyResult(source, to: &anchor)
        #expect(anchor.status == .scholarlyReference)
    }
}
