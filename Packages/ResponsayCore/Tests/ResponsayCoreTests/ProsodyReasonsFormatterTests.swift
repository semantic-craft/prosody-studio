import Testing
import Foundation
@testable import ResponsayCore

// 372 — the prosody "reason line" formatting (heading + tones + stress + linking +
// IPA + notes) lifted off QuickCaptureViewModel into a pure value type. It is a
// pure function of a ProsodyAnalysis, so it tests without a VM or any I/O.

private func word(_ text: String, stressed: Bool = false, nuclear: Bool = false, link: Link? = nil) -> Word {
    Word(text: text, syllables: [text], stressIndex: stressed ? 0 : nil,
         stressed: stressed, nuclear: nuclear, ipa: nil, linkToNext: link)
}

@Test func prosodyReasons_formatsHeadingTonesStressLinkingAndNotes() {
    let analysis = ProsodyAnalysis(
        text: "turn it off", isGeneratedExample: false, sourceWord: nil, ipa: "tɜːn ɪt ɒf",
        thoughtGroups: [ThoughtGroup(tone: .fall, words: [
            word("turn", stressed: true, link: .liaison),
            word("it"),
            word("off", nuclear: true)])],
        notes: "降到句末。")

    let reasons = ProsodyReasonsFormatter().reasons(from: analysis, heading: "测试标题")

    #expect(reasons.first == "测试标题")
    #expect(reasons.contains { $0.hasPrefix("升降调:") && $0.contains("降调") })
    #expect(reasons.contains { $0.hasPrefix("重音:") && $0.contains("turn") && $0.contains("off") })
    #expect(reasons.contains { $0.hasPrefix("连读:") && $0.contains("turn") && $0.contains("it") })
    #expect(reasons.contains { $0.hasPrefix("IPA:") })
    #expect(reasons.contains("降到句末。"))
}
