import Testing
import Foundation
@testable import ResponsayCore

/// 137 — 润色 (pure rewrite) contract. Verification: JSON / plain-text parse;
/// the result carries `rewritten` and nothing else.
struct PolishQuietResultTests {
    @Test func decodes_rewrittenKey() throws {
        let json = #"{"rewritten":"Could you give me some pointers?"}"#.data(using: .utf8)!
        let r = try JSONDecoder().decode(PolishQuietResult.self, from: json)
        #expect(r.rewritten == "Could you give me some pointers?")
    }

    @Test func decodes_textKey_fallback() throws {
        let json = #"{"text":"Let me check."}"#.data(using: .utf8)!
        let r = try JSONDecoder().decode(PolishQuietResult.self, from: json)
        #expect(r.rewritten == "Let me check.")
    }

    @Test func parse_jsonObject() {
        let r = PolishQuietResult.parse(#"{"rewritten":"Sounds good."}"#)
        #expect(r.rewritten == "Sounds good.")
    }

    @Test func parse_plainText_trimsWhitespace() {
        let r = PolishQuietResult.parse("  Sounds good to me.\n")
        #expect(r.rewritten == "Sounds good to me.")
    }

    @Test func request_encodesTone() throws {
        let req = PolishQuietRequest(text: "i wanna ask u sth", tone: .formal)
        let data = try JSONEncoder().encode(req)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(obj["tone"] as? String == "formal")
        #expect(obj["text"] as? String == "i wanna ask u sth")
    }

    @Test func tone_unknownValue_fallsBackToNatural() throws {
        let json = #"{"text":"x","tone":"shakespearean"}"#.data(using: .utf8)!
        struct Wrapper: Decodable { let tone: RewriteTone }
        let w = try JSONDecoder().decode(Wrapper.self, from: json)
        #expect(w.tone == .natural)
    }
}
