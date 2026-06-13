import Testing
@testable import ResponsayCore

/// Ported verbatim from the retired backend `hotword_match.test.mjs` (ADR-0011),
/// so the Swift app-side enforcer keeps the exact behavior the backend smoked
/// (issue 054). Three cycles: shape + core fix, spacing/acronym/CJK/multiword
/// windows, and the conservative edit-distance + false-positive guards.
struct HotwordHardMatchTests {

    // MARK: Cycle A — shape + the core single-token normalized fix

    @Test func emptyHotwords_leaveTranscriptUntouched() {
        let result = HotwordHardMatch.enforce("I used qwen3asr today", hotwords: [])
        #expect(result.text == "I used qwen3asr today")
        #expect(result.replacements.isEmpty)
    }

    @Test func blankText_isANoOp() {
        let result = HotwordHardMatch.enforce("   ", hotwords: ["Qwen3-ASR"])
        #expect(result.text == "   ")
        #expect(result.replacements.isEmpty)
    }

    @Test func normalizedExactNearMiss_isRewrittenToHotwordSpelling() {
        let result = HotwordHardMatch.enforce("I used qwen3asr today", hotwords: ["Qwen3-ASR"])
        #expect(result.text == "I used Qwen3-ASR today")
        #expect(result.replacements == [.init(from: "qwen3asr", to: "Qwen3-ASR")])
    }

    @Test func alreadyCorrectSpelling_isLeftAlone() {
        let result = HotwordHardMatch.enforce("I used Qwen3-ASR today", hotwords: ["Qwen3-ASR"])
        #expect(result.text == "I used Qwen3-ASR today")
        #expect(result.replacements.isEmpty)
    }

    @Test func enforcement_isIdempotent() {
        let once = HotwordHardMatch.enforce("I used qwen3asr today", hotwords: ["Qwen3-ASR"]).text
        let twice = HotwordHardMatch.enforce(once, hotwords: ["Qwen3-ASR"]).text
        #expect(twice == once)
    }

    // MARK: Cycle B — spacing / hyphen / acronym / CJK / multiword windows

    @Test func spaceSplitTerm_isRejoinedToHotwordSpelling() {
        let result = HotwordHardMatch.enforce("I used qwen3 asr today", hotwords: ["Qwen3-ASR"])
        #expect(result.text == "I used Qwen3-ASR today")
    }

    @Test func hyphenCasedVariant_isNormalizedToHotwordSpelling() {
        let result = HotwordHardMatch.enforce("ran qwen3-asr again", hotwords: ["Qwen3-ASR"])
        #expect(result.text == "ran Qwen3-ASR again")
    }

    @Test func letterSpelledAcronym_collapsesToHotwordSpelling() {
        let result = HotwordHardMatch.enforce("published in C L S C I last year", hotwords: ["CLSCI"])
        #expect(result.text == "published in CLSCI last year")
    }

    @Test func latinTermInChinese_isCorrectedWithoutTouchingTheChinese() {
        let result = HotwordHardMatch.enforce("我用 qwen3asr 写论文", hotwords: ["Qwen3-ASR"])
        #expect(result.text == "我用 Qwen3-ASR 写论文")
    }

    @Test func twoWordAuthorName_isCasedToHotwordSpelling() {
        let result = HotwordHardMatch.enforce("cited zhang wei in the intro", hotwords: ["Zhang Wei"])
        #expect(result.text == "cited Zhang Wei in the intro")
    }

    @Test func multipleHotwords_areEnforcedInASinglePass() {
        let result = HotwordHardMatch.enforce("zhang wei used qwen3 asr", hotwords: ["Zhang Wei", "Qwen3-ASR"])
        #expect(result.text == "Zhang Wei used Qwen3-ASR")
        #expect(result.replacements.count == 2)
    }

    // MARK: Cycle C — conservative edit-distance + false-positive guards

    @Test func oneCharMisspellingOfALongTerm_isRepaired() {
        let result = HotwordHardMatch.enforce("ran qwem3-asr again", hotwords: ["Qwen3-ASR"])
        #expect(result.text == "ran Qwen3-ASR again")
    }

    @Test func looselySimilarWord_isLeftUntouched() {
        let result = HotwordHardMatch.enforce("I like cotton fabric", hotwords: ["Kotlin"])
        #expect(result.text == "I like cotton fabric")
        #expect(result.replacements.isEmpty)
    }

    @Test func shortHotwords_requireAnExactNormalizedMatch() {
        // "API" must not capture the unrelated phrase "a pie".
        let result = HotwordHardMatch.enforce("I ate a pie", hotwords: ["API"])
        #expect(result.text == "I ate a pie")
        #expect(result.replacements.isEmpty)
    }

    @Test func shortHotword_stillFixesCasingOnAnExactNormalizedHit() {
        let result = HotwordHardMatch.enforce("the api call", hotwords: ["API"])
        #expect(result.text == "the API call")
    }

    @Test func closestHotwordWins_whenSeveralAreSimilar() {
        let result = HotwordHardMatch.enforce("we used llama", hotwords: ["LLaMA", "Gemma"])
        #expect(result.text == "we used LLaMA")
    }
}
