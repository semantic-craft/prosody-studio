import Testing
import Foundation
@testable import ResponsayCore

/// 138 — 表达纠正 (rewrite + teach) contract. Verification: schema validate;
/// out-of-bounds span repair; label-enum parse.
struct ExpressionCorrectionResultTests {

    // MARK: - Schema validate

    @Test func decodes_fullPayload() throws {
        let json = """
        {
          "rewritten": "Could you give me some pointers?",
          "issues": [
            {"span": {"start": 7, "end": 14}, "label": "word_choice", "note": "advices 不可数"}
          ],
          "why": [
            {"kind": "tone", "text": "更礼貌"},
            {"kind": "视角", "text": "从对方角度"}
          ],
          "practice": ["Could you walk me through it?"]
        }
        """.data(using: .utf8)!
        let r = try JSONDecoder().decode(ExpressionCorrectionResult.self, from: json)
        #expect(r.rewritten == "Could you give me some pointers?")
        #expect(r.issues.count == 1)
        #expect(r.issues[0].label == .wordChoice)
        #expect(r.why.count == 2)
        #expect(r.why[1].kind == .perspective)
        #expect(r.practice == ["Could you walk me through it?"])
    }

    @Test func decodes_minimal_onlyRewritten() throws {
        let json = #"{"rewritten":"Let me check."}"#.data(using: .utf8)!
        let r = try JSONDecoder().decode(ExpressionCorrectionResult.self, from: json)
        #expect(r.rewritten == "Let me check.")
        #expect(r.issues.isEmpty)
        #expect(r.why.isEmpty)
        #expect(r.practice.isEmpty)
    }

    // MARK: - why bridging + clamping

    @Test func bridges_reasons_intoWhy() throws {
        let json = #"{"text":"ok","reasons":["更口语","更自然"]}"#.data(using: .utf8)!
        let r = try JSONDecoder().decode(ExpressionCorrectionResult.self, from: json)
        #expect(r.why.count == 2)
        #expect(r.why.allSatisfy { $0.kind == .tone })
        #expect(r.why[0].text == "更口语")
    }

    @Test func clamps_why_toFive() throws {
        let notes = (1...8).map { #"{"kind":"tone","text":"n\#($0)"}"# }.joined(separator: ",")
        let json = #"{"rewritten":"x","why":[\#(notes)]}"#.data(using: .utf8)!
        let r = try JSONDecoder().decode(ExpressionCorrectionResult.self, from: json)
        #expect(r.why.count == ExpressionCorrectionResult.maxWhy)
    }

    // MARK: - Span repair

    @Test func repairsSpans_clampsOutOfBounds() throws {
        // original "please give advices" has 19 chars; one span runs past the end.
        let original = "please give advices"
        let r = ExpressionCorrectionResult(
            rewritten: "please give advice",
            issues: [
                RewriteIssue(span: TextSpan(start: 12, end: 99), label: .wordChoice),
                RewriteIssue(span: TextSpan(start: 0, end: 6), label: .grammar)
            ]
        )
        let fixed = r.repairingSpans(in: original)
        #expect(fixed.issues.count == 2)
        #expect(fixed.issues[0].span == TextSpan(start: 12, end: 19))   // clamped to length
        #expect(fixed.issues[1].span == TextSpan(start: 0, end: 6))     // untouched
    }

    @Test func repairsSpans_dropsInvertedOrEmpty() throws {
        let original = "hello world"
        let r = ExpressionCorrectionResult(
            rewritten: "hi",
            issues: [
                RewriteIssue(span: TextSpan(start: 8, end: 3), label: .other),   // inverted
                RewriteIssue(span: TextSpan(start: 50, end: 60), label: .other), // fully OOB
                RewriteIssue(span: TextSpan(start: 0, end: 5), label: .idiom)    // valid
            ]
        )
        let fixed = r.repairingSpans(in: original)
        #expect(fixed.issues.count == 1)
        #expect(fixed.issues[0].label == .idiom)
    }

    // MARK: - Span decode shapes

    @Test func decodes_locationLengthSpan() throws {
        let json = #"{"span":{"location":4,"length":3},"label":"grammar"}"#.data(using: .utf8)!
        let issue = try JSONDecoder().decode(RewriteIssue.self, from: json)
        #expect(issue.span == TextSpan(start: 4, end: 7))
    }

    // MARK: - Label enum parse

    @Test func label_unknown_parsesToOther() throws {
        let json = #"{"span":{"start":0,"end":1},"label":"vibes"}"#.data(using: .utf8)!
        let issue = try JSONDecoder().decode(RewriteIssue.self, from: json)
        #expect(issue.label == .other)
    }

    @Test func label_aliases_normalize() {
        #expect(IssueLabel.parse("word_choice") == .wordChoice)
        #expect(IssueLabel.parse("Collocation") == .wordChoice)
        #expect(IssueLabel.parse("idiomatic") == .idiom)
        #expect(IssueLabel.parse("REGISTER") == .tone)
    }

    @Test func label_missing_defaultsToOther() throws {
        let json = #"{"span":{"start":0,"end":2}}"#.data(using: .utf8)!
        let issue = try JSONDecoder().decode(RewriteIssue.self, from: json)
        #expect(issue.label == .other)
    }

    // MARK: - 润色 / 表达纠正 relationship

    @Test func asPolishQuiet_dropsTeaching() {
        let r = ExpressionCorrectionResult(
            rewritten: "Sounds good.",
            issues: [RewriteIssue(span: TextSpan(start: 0, end: 1), label: .tone)],
            why: [WhyNote(kind: .tone, text: "更自然")]
        )
        #expect(r.asPolishQuiet == PolishQuietResult(rewritten: "Sounds good."))
    }
}
