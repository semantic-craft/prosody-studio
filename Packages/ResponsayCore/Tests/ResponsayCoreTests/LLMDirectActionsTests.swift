import Testing
import Foundation
@testable import ResponsayCore

// Own stub class + static state, so the actions e2e suites never race the rewrite suite's
// LLMStubURLProtocol.
final class LLMActionsStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var data = Data()
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var requestBody = Data()
    nonisolated(unsafe) static var requestURL: URL?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requestURL = request.url
        Self.requestBody = request.httpBody ?? Self.readStream(request.httpBodyStream)
        let resp = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
    static func readStream(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}

private func actionsStubSession() -> URLSession {
    let cfg = URLSessionConfiguration.ephemeral
    cfg.protocolClasses = [LLMActionsStubURLProtocol.self]
    return URLSession(configuration: cfg)
}

private func completion(_ content: String) -> Data {
    try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]])
}

private func cloudEndpoint() -> LLMEndpoint {
    LLMEndpoint(providerId: "openai", baseURL: "https://api.openai.com/v1",
                model: "gpt-4.1", apiKey: "sk-1", thinkingEnabled: false)
}

private func kimiSearchEndpoint() -> LLMEndpoint {
    LLMEndpoint(providerId: "kimi", baseURL: "https://api.moonshot.cn/v1",
                model: "kimi-k2.6", apiKey: "sk-1", thinkingEnabled: true)
}

private func qwenSearchEndpoint() -> LLMEndpoint {
    LLMEndpoint(providerId: "qwen", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                model: "qwen-plus", apiKey: "sk-1", thinkingEnabled: false)
}

// MARK: - 241 Translate

struct TranslatePromptBuilderTests {
    @Test func namesTargetAndCarriesText() {
        let p = TranslatePromptBuilder.build(text: "我看看", target: .englishUS)
        #expect(p.system.contains("American English"))
        #expect(p.user.contains("我看看"))
        #expect(p.user.contains("en-US"))
        #expect(TranslatePromptBuilder.build(text: "x", target: .german).system.contains("German"))
    }
}

// MARK: - 242 Express

struct ExpressPromptBuilderTests {
    @Test func registerDirectivesAreDistinct() {
        let regs: [CoachRegister] = [.casual, .neutral, .formal, .academic]
        #expect(Set(regs.map { ExpressPromptBuilder.coachRegisterDirective($0) }).count == 4)
        #expect(ExpressPromptBuilder.coachRegisterDirective(.academic).contains("学术"))
    }

    @Test func contextLines_respectBudgetAndPriority() {
        let ctx = ExpressionContext(
            appName: "TextEdit", selectedText: "the attached brief", hotwords: ["CLSCI"])
        let lines = ExpressPromptBuilder.contextLines(ctx)
        #expect(lines.first?.contains("the attached brief") == true)   // highest priority first
        #expect(lines.contains { $0.contains("CLSCI") })
        #expect(ExpressPromptBuilder.contextLines(nil).isEmpty)
    }

    @Test func build_putsRegisterAndUtteranceIn() {
        let p = ExpressPromptBuilder.build(intent: "please give me some advices", context: nil, register: .academic)
        #expect(p.system.contains("学术"))
        #expect(p.user.contains("please give me some advices"))
        #expect(p.system.contains("{\"idiomatic\": string"))
    }
}

// MARK: - 244 Prosody prompt

struct ProsodyPromptBuilderTests {
    @Test func carriesSchemaAndInput() {
        let p = ProsodyPromptBuilder.build(text: "I'll call you.")
        #expect(p.system.contains("thoughtGroups"))
        #expect(p.user.contains("I'll call you."))
    }
}

// MARK: - e2e (stubbed transport)

// All network e2e tests share `LLMActionsStubURLProtocol`'s static state, so they live in ONE
// serialized suite — separate `.serialized` suites would still run in parallel and race.
@Suite(.serialized)
struct DirectActionsE2ETests {
    @Test func translate_parsesEnvelope_setsTargetAndOriginal() async throws {
        LLMActionsStubURLProtocol.status = 200
        LLMActionsStubURLProtocol.data = completion(#"{"text":"Let me check.","notes":["meaning-first"]}"#)
        let api = DirectTextTranslationAPI(endpoint: cloudEndpoint(), session: actionsStubSession())
        let r = try await api.translate("我看看", target: .englishUS)
        #expect(r.text == "Let me check.")
        #expect(r.original == "我看看")
        #expect(r.targetLanguage == "en-US")
        #expect(r.notes == ["meaning-first"])
    }

    @Test func express_parsesAllFields_originalFromIntent() async throws {
        LLMActionsStubURLProtocol.status = 200
        LLMActionsStubURLProtocol.data = completion(
            #"{"idiomatic":"Could you give me some pointers?","alternatives":["Any tips?"],"reasons":["更口语"],"thinkingShift":"中式名词堆叠 / 美式动词请求"}"#)
        let api = DirectCoachAPI(endpoint: cloudEndpoint(), register: .casual, session: actionsStubSession())
        let r = try await api.express("please give me some advices")
        #expect(r.idiomatic == "Could you give me some pointers?")
        #expect(r.original == "please give me some advices")
        #expect(r.alternatives == ["Any tips?"])
        #expect(r.thinkingShift.contains("美式"))
    }

    @Test func analyze_decodesProsodyAnalysis() async throws {
        LLMActionsStubURLProtocol.status = 200
        LLMActionsStubURLProtocol.data = completion(
            #"{"text":"Hi.","isGeneratedExample":false,"ipa":"/haɪ/","thoughtGroups":[{"tone":"fall","words":[{"text":"Hi","syllables":["Hi"],"stressIndex":0,"stressed":true,"nuclear":true}]}]}"#)
        let api = DirectCoachAPI(endpoint: cloudEndpoint(), register: .casual, session: actionsStubSession())
        let r = try await api.analyze("Hi.")
        #expect(r.text == "Hi.")
        #expect(r.thoughtGroups.first?.tone == .fall)
        #expect(r.thoughtGroups.first?.words.first?.nuclear == true)
        try ProsodyValidator.validateProsody(r)
    }

    @Test func analyze_repairsWordOrderMismatchBeforeReturning() async throws {
        LLMActionsStubURLProtocol.status = 200
        LLMActionsStubURLProtocol.data = completion(
            #"{"text":"totally different text","isGeneratedExample":false,"ipa":"","thoughtGroups":[{"tone":"fall","words":[{"text":"world","syllables":["world"],"stressIndex":0,"stressed":false,"nuclear":false},{"text":"hello","syllables":["hello"],"stressIndex":0,"stressed":true,"nuclear":true}]}]}"#)
        let api = DirectCoachAPI(endpoint: cloudEndpoint(), register: .casual, session: actionsStubSession())
        let r = try await api.analyze("hello world")
        #expect(r.text == "world hello")
        try ProsodyValidator.validateProsody(r)
    }

    @Test func analyze_normalizesEverydayEnglishBeforeReturning() async throws {
        LLMActionsStubURLProtocol.status = 200
        LLMActionsStubURLProtocol.data = completion(
            #"{"text":"the quick brown fox","isGeneratedExample":false,"ipa":"","thoughtGroups":[{"tone":"fall","words":[{"text":"the","syllables":["the"],"stressIndex":0,"stressed":true,"nuclear":true},{"text":"quick","syllables":["quick"],"stressIndex":0,"stressed":true,"nuclear":true},{"text":"brown","syllables":["brown"],"stressIndex":0,"stressed":true,"nuclear":false},{"text":"fox","syllables":["fox"],"stressIndex":0,"stressed":true,"nuclear":false}]}]}"#)
        let api = DirectCoachAPI(endpoint: cloudEndpoint(), register: .casual, session: actionsStubSession())
        let r = try await api.analyze("the quick brown fox")
        let words = r.thoughtGroups[0].words
        #expect(words.first { $0.text == "the" }?.stressed == false)
        #expect(words.filter(\.stressed).count <= 2)
        #expect(words.filter(\.nuclear).map(\.text) == ["fox"])
    }

    @Test func analyze_throwsOnUndecodableJSON() async throws {
        LLMActionsStubURLProtocol.status = 200
        LLMActionsStubURLProtocol.data = completion(#"{"text":"only text, no thoughtGroups"}"#)
        let api = DirectCoachAPI(endpoint: cloudEndpoint(), register: .casual, session: actionsStubSession())
        await #expect(throws: LLMError.self) { _ = try await api.analyze("x") }
    }

    @Test func analyze_throwsOnUnrepairableProsodyShape() async throws {
        LLMActionsStubURLProtocol.status = 200
        LLMActionsStubURLProtocol.data = completion(
            #"{"text":"hello","isGeneratedExample":false,"ipa":"","thoughtGroups":[]}"#)
        let api = DirectCoachAPI(endpoint: cloudEndpoint(), register: .casual, session: actionsStubSession())
        await #expect(throws: LLMError.badJSON("prosody decode/validation failed")) {
            _ = try await api.analyze("hello")
        }
    }

    // 243 legal: the assembled prompt is sent to the provider; the raw model text becomes
    // `output` for the validator (the backend route was a pure passthrough).
    @Test func legal_executesAndReturnsRawOutputWithRunId() async throws {
        LLMActionsStubURLProtocol.status = 200
        LLMActionsStubURLProtocol.data = completion(#"{"cardType":"draft","text":"本段建议……[待核]"}"#)
        let exec = DirectLegalSkillExecutorAPI(
            endpoint: cloudEndpoint(), session: actionsStubSession(), runIdProvider: { "run-1" })
        let request = LegalSkillExecutionRequest(
            skillId: "legal.report.case", systemPrompt: "SYS", userPrompt: "USR", modelRoute: .cloudAllowed)
        let resp = try await exec.executeSkill(request)
        #expect(resp.output == #"{"cardType":"draft","text":"本段建议……[待核]"}"#)
        #expect(resp.runId == "run-1")
        #expect(resp.provider == "openai")
    }

    @Test func legal_localOnlyOnCloudEndpoint_refuses() async throws {
        let exec = DirectLegalSkillExecutorAPI(endpoint: cloudEndpoint(), session: actionsStubSession())
        let request = LegalSkillExecutionRequest(
            skillId: "s", systemPrompt: "S", userPrompt: "U", modelRoute: .localOnly)
        await #expect(throws: LLMError.self) { _ = try await exec.executeSkill(request) }
    }

    @Test func legal_searchVerification_sendsSearchEnabledAndParsesSource() async throws {
        LLMActionsStubURLProtocol.status = 200
        LLMActionsStubURLProtocol.requestBody = Data()
        LLMActionsStubURLProtocol.requestURL = nil
        LLMActionsStubURLProtocol.data = try JSONSerialization.data(withJSONObject: [
            "choices": [[
                "message": [
                    "content": "已找到国家法律法规数据库来源。",
                    "search_results": [[
                        "title": "中华人民共和国民法典",
                        "url": "https://flk.npc.gov.cn/detail2.html",
                        "content": "第五百七十七条 当事人一方不履行合同义务..."
                    ]]
                ]
            ]]
        ])
        let exec = DirectLegalSkillExecutorAPI(endpoint: kimiSearchEndpoint(), session: actionsStubSession())
        let anchor = VerificationAnchor(
            id: "law:1", label: "《民法典》第577条", kind: .law,
            query: "《民法典》第577条")

        let source = try await exec.searchVerification(anchor, route: .cloudAllowed)

        #expect(source?.title == "中华人民共和国民法典")
        #expect(source?.url == "https://flk.npc.gov.cn/detail2.html")
        let body = try JSONSerialization.jsonObject(with: LLMActionsStubURLProtocol.requestBody) as? [String: Any]
        let tools = try #require(body?["tools"] as? [[String: Any]])
        #expect((tools.first?["function"] as? [String: Any])?["name"] as? String == "$web_search")
        #expect((body?["thinking"] as? [String: Any])?["type"] as? String == "disabled")
    }

    @Test func legal_searchVerification_qwenUsesDashScopeNativeSourceResults() async throws {
        LLMActionsStubURLProtocol.status = 200
        LLMActionsStubURLProtocol.requestBody = Data()
        LLMActionsStubURLProtocol.requestURL = nil
        LLMActionsStubURLProtocol.data = try JSONSerialization.data(withJSONObject: [
            "output": [
                "choices": [[
                    "message": [
                        "content": "检索到《民法典》第五百七十七条的官方来源。"
                    ]
                ]],
                "search_info": [
                    "search_results": [
                        [
                            "site_name": "百科",
                            "title": "民法典解读",
                            "url": "https://example.com/minfadian"
                        ],
                        [
                            "site_name": "国家法律法规数据库",
                            "title": "中华人民共和国民法典",
                            "url": "https://flk.npc.gov.cn/detail2.html"
                        ]
                    ]
                ]
            ]
        ])
        let exec = DirectLegalSkillExecutorAPI(endpoint: qwenSearchEndpoint(), session: actionsStubSession())
        let anchor = VerificationAnchor(
            id: "law:1", label: "《民法典》第577条", kind: .law,
            query: "《民法典》第577条")

        let source = try await exec.searchVerification(anchor, route: .cloudAllowed)

        #expect(LLMActionsStubURLProtocol.requestURL?.absoluteString
                == "https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation")
        #expect(source?.title == "中华人民共和国民法典")
        #expect(source?.url == "https://flk.npc.gov.cn/detail2.html")
        #expect(source?.provider == "qwen")
        let body = try JSONSerialization.jsonObject(with: LLMActionsStubURLProtocol.requestBody) as? [String: Any]
        let parameters = try #require(body?["parameters"] as? [String: Any])
        #expect(parameters["enable_search"] as? Bool == true)
        #expect(parameters["result_format"] as? String == "message")
        let options = try #require(parameters["search_options"] as? [String: Any])
        #expect(options["forced_search"] as? Bool == true)
        #expect(options["enable_source"] as? Bool == true)
        #expect(options["search_strategy"] as? String == "max")
    }

    // 240 Validate: a real chat call succeeds (returns reply) and surfaces HTTP errors.
    @Test func connectivityCheck_returnsReply_andThrowsOnHTTPError() async throws {
        LLMActionsStubURLProtocol.status = 200
        LLMActionsStubURLProtocol.data = completion("OK")
        let reply = try await LLMConnectivityCheck.validate(endpoint: cloudEndpoint(), session: actionsStubSession())
        #expect(reply == "OK")

        LLMActionsStubURLProtocol.status = 401
        LLMActionsStubURLProtocol.data = #"{"error":"bad key"}"#.data(using: .utf8)!
        await #expect(throws: LLMError.self) {
            _ = try await LLMConnectivityCheck.validate(endpoint: cloudEndpoint(), session: actionsStubSession())
        }
    }
}
