import Testing
import Foundation
@testable import ResponsayCore

/// 144 v2 — app-side connected-speech detection.
struct LiaisonRulesTests {
    private let rules = LiaisonRules()

    @Test func consonantToVowel_isLiaison() {
        #expect(rules.link(leftIPA: "hoʊldz", rightIPA: "ʌp") == .liaison)   // holds_up
        #expect(rules.link(leftIPA: "kæn", rightIPA: "aɪ") == .liaison)      // can_I
    }

    @Test func vowelToVowel_isIntrusion() {
        #expect(rules.link(leftIPA: "goʊ", rightIPA: "ɑn") == .intrusion)    // go_on
        #expect(rules.link(leftIPA: "aɪ", rightIPA: "æm") == .intrusion)     // I_am
    }

    @Test func identicalConsonant_isElision() {
        #expect(rules.link(leftIPA: "gʊd", rightIPA: "deɪ") == .elision)     // good_day  /d/+/d/
    }

    @Test func distinctConsonants_isNil() {
        #expect(rules.link(leftIPA: "kæt", rightIPA: "sæt") == nil)          // t + s, distinct → no link
    }

    @Test func vowelEndConsonantStart_isNil() {
        #expect(rules.link(leftIPA: "ðə", rightIPA: "bʊk") == nil)           // ə(vowel) → b(cons) = nothing
    }

    @Test func stripsStressAndLengthMarks() {
        // leading ˈ and length ː must not be mistaken for phonemes.
        #expect(rules.link(leftIPA: "ˈhoʊldz", rightIPA: "ˈʌp") == .liaison)
        #expect(rules.link(leftIPA: "ʃʊr", rightIPA: "ɔːl") == .liaison)     // sure_all  r+ɔ
    }

    @Test func missingIPA_isNil() {
        #expect(rules.link(leftIPA: nil, rightIPA: "ʌp") == nil)
        #expect(rules.link(leftIPA: "hoʊldz", rightIPA: nil) == nil)
    }
}
