import Testing
import Foundation
@testable import ResponsayCore

final class DirectCoachProsodyShapeStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var data = Data()
    nonisolated(unsafe) static var status = 200

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.status,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func directCoachProsodyShapeSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [DirectCoachProsodyShapeStubURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func directCoachProsodyShapeEndpoint() -> LLMEndpoint {
    LLMEndpoint(
        providerId: "openai",
        baseURL: "https://api.openai.com/v1",
        model: "gpt-4.1",
        apiKey: "sk-1",
        thinkingEnabled: false
    )
}

private func directCoachCompletion(_ content: String) -> Data {
    try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]])
}

@Suite(.serialized)
struct DirectCoachProsodyShapeTests {
    @Test func analyzeRepairsSyllableStressShapeBeforeReturning() async throws {
        DirectCoachProsodyShapeStubURLProtocol.status = 200
        DirectCoachProsodyShapeStubURLProtocol.data = directCoachCompletion(
            #"{"text":"finish","isGeneratedExample":false,"ipa":"","thoughtGroups":[{"tone":"fall","words":[{"text":"finish","syllables":[],"stressed":true,"nuclear":true}]}]}"#
        )
        let api = DirectCoachAPI(
            endpoint: directCoachProsodyShapeEndpoint(),
            register: .casual,
            session: directCoachProsodyShapeSession()
        )
        let result = try await api.analyze("finish")
        let word = try #require(result.thoughtGroups.first?.words.first)

        #expect(word.syllables == ["finish"])
        #expect(word.stressIndex == 0)
        try ProsodyValidator.validateProsody(result)
    }
}
