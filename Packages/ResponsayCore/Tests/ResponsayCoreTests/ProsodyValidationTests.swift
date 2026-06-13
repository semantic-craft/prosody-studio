import Testing
import Foundation
@testable import ResponsayCore

/// 143 — ProsodyAnalysis validate / repair / normalize.
/// Verification: illegal `tone` rejected; word-order mismatch repaired or failed; stress-sparse rule.
struct ProsodyValidationTests {
    private func word(_ text: String, stressed: Bool = false, nuclear: Bool = false) -> Word {
        Word(text: text, syllables: [text], stressIndex: stressed ? 0 : nil,
             stressed: stressed, nuclear: nuclear, ipa: nil, linkToNext: nil)
    }

    private func analysis(text: String, _ words: [Word], tone: Tone = .fall) -> ProsodyAnalysis {
        ProsodyAnalysis(text: text, isGeneratedExample: false, sourceWord: nil, ipa: "",
                        thoughtGroups: [ThoughtGroup(tone: tone, words: words)], notes: nil)
    }

    // MARK: - illegal tone rejected (decode level)

    @Test func illegalTone_failsToDecode() {
        let json = #"{"tone":"sideways","words":[]}"#.data(using: .utf8)!
        #expect((try? JSONDecoder().decode(ThoughtGroup.self, from: json)) == nil)
    }

    @Test func legalTone_decodes() throws {
        let json = #"{"tone":"fall-rise","words":[]}"#.data(using: .utf8)!
        let group = try JSONDecoder().decode(ThoughtGroup.self, from: json)
        #expect(group.tone == .fallRise)
    }

    // MARK: - validate

    @Test func wellFormed_passesValidation() throws {
        let a = analysis(text: "hello world", [word("hello"), word("world", stressed: true, nuclear: true)])
        try ProsodyValidator.validateProsody(a)   // no throw
    }

    @Test func emptyThoughtGroups_throws() {
        let a = ProsodyAnalysis(text: "x", isGeneratedExample: false, sourceWord: nil, ipa: "",
                                thoughtGroups: [], notes: nil)
        #expect(throws: ProsodyValidationError.self) { try ProsodyValidator.validateProsody(a) }
    }

    @Test func wordOrderMismatch_throws() {
        let a = analysis(text: "hello world", [word("world"), word("hello", nuclear: true)])
        #expect(throws: ProsodyValidationError.self) { try ProsodyValidator.validateProsody(a) }
    }

    @Test func emptySyllables_throw() {
        let bad = Word(text: "finish", syllables: [], stressIndex: nil,
                       stressed: false, nuclear: true, ipa: nil, linkToNext: nil)
        let a = analysis(text: "finish", [bad])
        #expect(throws: ProsodyValidationError.self) { try ProsodyValidator.validateProsody(a) }
    }

    @Test func outOfBoundsStressIndex_throws() {
        let bad = Word(text: "finish", syllables: ["fin", "ish"], stressIndex: 4,
                       stressed: true, nuclear: true, ipa: nil, linkToNext: nil)
        let a = analysis(text: "finish", [bad])
        #expect(throws: ProsodyValidationError.self) { try ProsodyValidator.validateProsody(a) }
    }

    @Test func stressedWithoutStressIndex_throws() {
        let bad = Word(text: "finish", syllables: ["fin", "ish"], stressIndex: nil,
                       stressed: true, nuclear: true, ipa: nil, linkToNext: nil)
        let a = analysis(text: "finish", [bad])
        #expect(throws: ProsodyValidationError.self) { try ProsodyValidator.validateProsody(a) }
    }

    // MARK: - repair

    @Test func repair_rebuildsTextFromWords_thenValidates() throws {
        // text disagrees with the word stream → repair makes text authoritative.
        let a = analysis(text: "totally different text", [word("world"), word("hello", nuclear: true)])
        let repaired = try ProsodyValidator.repairProsodyShape(a)
        #expect(repaired.text == "world hello")
        try ProsodyValidator.validateProsody(repaired)   // now consistent
    }

    @Test func repair_addsNuclearWhenMissing() throws {
        let a = analysis(text: "hello world", [word("hello"), word("world")])  // no nuclear
        let repaired = try ProsodyValidator.repairProsodyShape(a)
        let nuclei = repaired.thoughtGroups.flatMap { $0.words.filter(\.nuclear) }
        #expect(nuclei.count == 1)
        #expect(nuclei.first?.text == "world")
    }

    @Test func repair_sanitizesSyllablesAndStressIndexes() throws {
        let emptySyllables = Word(text: "finish", syllables: [], stressIndex: nil,
                                  stressed: true, nuclear: true, ipa: nil, linkToNext: nil)
        let badStressIndex = Word(text: "today", syllables: ["to", "day"], stressIndex: 7,
                                  stressed: true, nuclear: false, ipa: nil, linkToNext: nil)
        let a = analysis(text: "finish today", [emptySyllables, badStressIndex])
        let repaired = try ProsodyValidator.repairProsodyShape(a)
        let words = repaired.thoughtGroups[0].words

        #expect(words[0].syllables == ["finish"])
        #expect(words[0].stressIndex == 0)
        #expect(words[1].stressIndex == 1)
        try ProsodyValidator.validateProsody(repaired)
    }

    @Test func repair_failsOnEmpty() {
        let a = ProsodyAnalysis(text: "x", isGeneratedExample: false, sourceWord: nil, ipa: "",
                                thoughtGroups: [], notes: nil)
        #expect(throws: ProsodyValidationError.self) { _ = try ProsodyValidator.repairProsodyShape(a) }
    }

    // MARK: - normalize (stress-sparse + single nucleus)

    @Test func normalize_thinsOverStressing() {
        // every word stressed → after normalize, ≤ half stay stressed.
        let words = ["the", "quick", "brown", "fox", "jumps", "now"].map { word($0, stressed: true) }
        let a = analysis(text: "the quick brown fox jumps now", words)
        let normalized = ProsodyValidator.normalizeProsodyForEverydayEnglish(a)
        let stressedCount = normalized.thoughtGroups[0].words.filter(\.stressed).count
        #expect(stressedCount <= 3)                                   // ≤ ceil(6/2)
        // the function word "the" should not carry stress
        let theWord = normalized.thoughtGroups[0].words.first { $0.text == "the" }
        #expect(theWord?.stressed == false)
    }

    @Test func normalize_collapsesToOneNucleus() {
        let words = [word("a", stressed: true, nuclear: true),
                     word("big", stressed: true, nuclear: true),
                     word("deal", stressed: true)]
        let a = analysis(text: "a big deal", words)
        let normalized = ProsodyValidator.normalizeProsodyForEverydayEnglish(a)
        let nuclei = normalized.thoughtGroups[0].words.filter(\.nuclear)
        #expect(nuclei.count == 1)
        #expect(nuclei.first?.text == "deal")     // last stressed becomes the nucleus
        #expect(nuclei.first?.stressed == true)   // nuclear implies stressed
    }

    @Test func normalize_promotedNucleusGetsValidStressIndex() throws {
        let a = analysis(text: "hello", [
            Word(text: "hello", syllables: ["hello"], stressIndex: nil,
                 stressed: false, nuclear: false, ipa: nil, linkToNext: nil),
        ])
        let normalized = ProsodyValidator.normalizeProsodyForEverydayEnglish(a)
        let promoted = normalized.thoughtGroups[0].words[0]

        #expect(promoted.nuclear == true)
        #expect(promoted.stressed == true)
        #expect(promoted.stressIndex == 0)
        try ProsodyValidator.validateProsody(normalized)
    }
}
