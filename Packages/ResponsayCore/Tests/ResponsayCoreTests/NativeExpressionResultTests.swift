import Testing
import Foundation
@testable import ResponsayCore

/// 140 — native English expression (中文意图 → 地道英文 + 中文 coaching).
/// Verification: contract parse; distinct route from 137.
struct NativeExpressionResultTests {
    @Test func decodes_englishAndStructuredWhy() throws {
        let json = """
        {"english":"Could you give me a hand with this?",
         "why":[{"kind":"tone","text":"用疑问句更礼貌"},{"kind":"register","text":"口语场合自然"}],
         "alternatives":["Mind helping me out?"]}
        """.data(using: .utf8)!
        let r = try JSONDecoder().decode(NativeExpressionResult.self, from: json)
        #expect(r.english == "Could you give me a hand with this?")
        #expect(r.why.count == 2)
        #expect(r.why[1].kind == .register)
        #expect(r.alternatives == ["Mind helping me out?"])
    }

    @Test func bridges_idiomaticAndReasons_fromExpressRoute() throws {
        // The existing /express shape (idiomatic + reasons[]) still decodes.
        let json = #"{"idiomatic":"Let me look into it.","reasons":["更主动","更地道"]}"#.data(using: .utf8)!
        let r = try JSONDecoder().decode(NativeExpressionResult.self, from: json)
        #expect(r.english == "Let me look into it.")
        #expect(r.why.count == 2)
        #expect(r.why.allSatisfy { $0.kind == .tone })
    }

    @Test func keepsTeaching_notCollapsedToPolish() throws {
        // 140 retains `why` — it is NOT the rewrite-only 润色 shape (137).
        let json = #"{"english":"I'd appreciate your input.","reasons":["语气更得体"]}"#.data(using: .utf8)!
        let r = try JSONDecoder().decode(NativeExpressionResult.self, from: json)
        #expect(r.why.isEmpty == false)
        // PolishQuietResult has no `why` to carry — distinct contract.
        let polish = PolishQuietResult.parse(#"{"rewritten":"I'd appreciate your input."}"#)
        #expect(polish.rewritten == r.english)
    }

    @Test func requestEncodesIntentAndTone() throws {
        let req = NativeExpressionRequest(intent: "我想委婉地催一下进度", tone: .formal)
        let data = try JSONEncoder().encode(req)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(obj["intent"] as? String == "我想委婉地催一下进度")
        #expect(obj["tone"] as? String == "formal")
    }
}
