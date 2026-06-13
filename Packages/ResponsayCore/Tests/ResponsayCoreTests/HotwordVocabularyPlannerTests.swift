import Testing
import Foundation
@testable import ResponsayCore

/// DashScope vocabulary planning rules (custom-hot-words-user-guide), pinned
/// after the 2026-06-11 live verification ("response" → "Responsay").
@Suite struct HotwordVocabularyPlannerTests {
    @Test func plansCJKAndASCIIWithInferredLang() {
        let planned = HotwordVocabularyPlanner.plan(["枉法裁判", "Responsay"])
        #expect(planned.count == 2)
        #expect(planned[0].lang == "zh")
        #expect(planned[1].lang == "en")
        #expect(planned.allSatisfy { $0.weight == 4 })  // documented starting point
    }

    @Test func dropsOverlongEntries() {
        // Non-ASCII > 15 chars and ASCII > 7 space-separated parts are invalid.
        let tooLongCJK = String(repeating: "法", count: 16)
        let tooLongASCII = "one two three four five six seven eight"
        let planned = HotwordVocabularyPlanner.plan([tooLongCJK, tooLongASCII, "合同法"])
        #expect(planned.map(\.text) == ["合同法"])
    }

    @Test func boundaryLengthsAreKept() {
        let cjk15 = String(repeating: "法", count: 15)
        let ascii7 = "a b c d e f g"
        let planned = HotwordVocabularyPlanner.plan([cjk15, ascii7])
        #expect(planned.count == 2)
    }

    @Test func dedupesCaseInsensitivelyAndTrims() {
        let planned = HotwordVocabularyPlanner.plan([" Responsay ", "responsay", "RESPONSAY"])
        #expect(planned.count == 1)
        #expect(planned[0].text == "Responsay")
    }

    @Test func capsAtFiveHundred() {
        let many = (0..<600).map { "词\($0)" }
        #expect(HotwordVocabularyPlanner.plan(many).count == HotwordVocabularyPlanner.maxEntries)
    }

    @Test func fingerprintStableAndOrderSensitive() {
        let a = HotwordVocabularyPlanner.plan(["甲", "乙"])
        let b = HotwordVocabularyPlanner.plan(["甲", "乙"])
        let c = HotwordVocabularyPlanner.plan(["乙", "甲"])
        #expect(HotwordVocabularyPlanner.fingerprint(a) == HotwordVocabularyPlanner.fingerprint(b))
        #expect(HotwordVocabularyPlanner.fingerprint(a) != HotwordVocabularyPlanner.fingerprint(c))
    }

    @Test func emptyInputPlansNothing() {
        #expect(HotwordVocabularyPlanner.plan(["", "   "]).isEmpty)
    }

    // MARK: - FunASRBatch wav handling

    @Test func batchAPIStripsWAVHeader() {
        let samples: [Int16] = [100, -100, 2_000]
        let wav = PCMWAVSegmenter.wavData(samples[...])
        let pcm = FunASRBatchTranscriptionAPI.pcmPayload(from: wav, mimeType: "audio/wav")
        #expect(pcm.count == samples.count * 2)
        #expect(pcm == wav.suffix(samples.count * 2))
    }

    @Test func batchAPIPassesRawPCMThrough() {
        let raw = Data([0x01, 0x02, 0x03, 0x04])
        #expect(FunASRBatchTranscriptionAPI.pcmPayload(from: raw, mimeType: "audio/pcm") == raw)
    }
}
