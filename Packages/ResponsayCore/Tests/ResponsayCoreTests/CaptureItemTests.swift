import Testing
import Foundation
@testable import ResponsayCore

@Test func captureItem_codableRoundTrip() throws {
    let item = CaptureItem(
        sourceText: "i want fix this bug",
        language: "en-US",
        idiomatic: "I want to fix this bug.",
        reasons: ["缺少不定式 to", "want 后接 to-infinitive"]
    )
    let data = try JSONEncoder().encode(item)
    let decoded = try JSONDecoder().decode(CaptureItem.self, from: data)
    #expect(decoded.sourceText == item.sourceText)
    #expect(decoded.idiomatic == item.idiomatic)
    #expect(decoded.reasons == item.reasons)
    #expect(decoded.id == item.id)
}

@Test func expressionResult_decodesBackendShape() throws {
    let json = """
    {"idiomatic":"I want to fix this bug.","original":"i want fix this bug","reasons":["缺 to"]}
    """.data(using: .utf8)!
    let r = try JSONDecoder().decode(ExpressionResult.self, from: json)
    #expect(r.idiomatic == "I want to fix this bug.")
    #expect(r.original == "i want fix this bug")
    #expect(r.reasons == ["缺 to"])
}
