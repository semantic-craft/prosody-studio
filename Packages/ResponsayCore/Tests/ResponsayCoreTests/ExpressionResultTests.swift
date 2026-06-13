import Testing
import Foundation
@testable import ResponsayCore

struct ExpressionResultTests {
    @Test func decodes_newFields_thinkingShiftAndAlternatives() throws {
        let json = """
        {"idiomatic":"Could you give me some pointers?","original":"please give me some advices",
         "reasons":["a"],"thinkingShift":"中式…/美式…","alternatives":["Any tips?"]}
        """.data(using: .utf8)!
        let r = try JSONDecoder().decode(ExpressionResult.self, from: json)
        #expect(r.thinkingShift.contains("美式"))
        #expect(r.alternatives == ["Any tips?"])
    }

    @Test func decodes_legacyJSON_withoutNewFields_usesDefaults() throws {
        let json = #"{"idiomatic":"Let me check.","original":"我看看","reasons":["更口语"]}"#
            .data(using: .utf8)!
        let r = try JSONDecoder().decode(ExpressionResult.self, from: json)
        #expect(r.thinkingShift.isEmpty)
        #expect(r.alternatives.isEmpty)
    }
}
