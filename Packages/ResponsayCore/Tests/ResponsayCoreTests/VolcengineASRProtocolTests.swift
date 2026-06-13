import Testing
import Foundation
@testable import ResponsayCore

/// Pure protocol helpers for Volcengine 火山引擎 streaming ASR — hotword context,
/// the first-frame JSON payload, and server-result text extraction. Ported from
/// the openless Rust `asr::volcengine` (the non-socket parts).
@Suite struct VolcengineASRProtocolTests {

    // MARK: Credentials

    @Test func defaultResourceIDIsSaucDuration() {
        #expect(VolcengineCredentials.defaultResourceID == "volc.seedasr.sauc.duration")
    }

    @Test func credentialsCompleteOnlyWhenAllFieldsPresent() {
        #expect(VolcengineCredentials(appId: "k", accessToken: "t", resourceID: "r").isComplete)
        #expect(!VolcengineCredentials(appId: "", accessToken: "t", resourceID: "r").isComplete)
        #expect(!VolcengineCredentials(appId: " ", accessToken: "t", resourceID: "r").isComplete)
    }

    // MARK: Hotword context

    @Test func hotwordContextDedupesCaseInsensitivelyAndCaps() throws {
        var entries = [
            VolcengineHotword(phrase: "Foo", enabled: true),
            VolcengineHotword(phrase: "foo", enabled: true),     // dup (case-insensitive)
            VolcengineHotword(phrase: "  ", enabled: true),      // blank
            VolcengineHotword(phrase: "Bar", enabled: false),    // disabled
            VolcengineHotword(phrase: "Baz", enabled: true),
        ]
        for index in 0..<200 {
            entries.append(VolcengineHotword(phrase: "w\(index)", enabled: true))
        }
        let context = try #require(VolcengineASRProtocol.hotwordContext(entries))
        #expect(context.contains("\"hotwords\""))
        #expect(context.contains("Foo"))
        #expect(context.contains("Baz"))
        #expect(!context.contains("Bar"))   // disabled never injected

        // Cap at 24 distinct phrases (~100-token streaming 直传 budget).
        let object = try JSONSerialization.jsonObject(with: Data(context.utf8)) as? [String: Any]
        let words = try #require(object?["hotwords"] as? [[String: Any]])
        #expect(words.count == VolcengineASRProtocol.hotwordCap)
        // No duplicate "Foo"/"foo" — only one survives.
        let foos = words.compactMap { $0["word"] as? String }.filter { $0.lowercased() == "foo" }
        #expect(foos.count == 1)
    }

    @Test func hotwordContextReturnsNilWhenAllDisabledOrEmpty() {
        #expect(VolcengineASRProtocol.hotwordContext([
            VolcengineHotword(phrase: "Foo", enabled: false)
        ]) == nil)
        #expect(VolcengineASRProtocol.hotwordContext([]) == nil)
    }

    // MARK: First-frame payload

    @Test func firstFramePayloadHasModelAudioAndUser() throws {
        let data = VolcengineASRProtocol.firstFramePayload(connectID: "conn-123", hotwords: [])
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        let request = try #require(root["request"] as? [String: Any])
        #expect(request["model_name"] as? String == "bigmodel")
        #expect(request["enable_itn"] as? Bool == true)
        #expect(request["enable_punc"] as? Bool == true)
        #expect(request["show_utterances"] as? Bool == true)
        #expect(request["corpus"] == nil)    // no hotwords → no corpus dict
        #expect(request["context"] == nil)   // never at top level (server ignores it there)

        let audio = try #require(root["audio"] as? [String: Any])
        #expect(audio["format"] as? String == "pcm")
        #expect(audio["rate"] as? Int == 16000)
        #expect(audio["bits"] as? Int == 16)
        #expect(audio["channel"] as? Int == 1)
        #expect(audio["codec"] as? String == "raw")

        let user = try #require(root["user"] as? [String: Any])
        #expect(user["uid"] as? String == "conn-123")
    }

    @Test func firstFramePayloadIncludesAccelerationAndDDCParams() throws {
        let data = VolcengineASRProtocol.firstFramePayload(connectID: "c", hotwords: [])
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let request = try #require(root["request"] as? [String: Any])

        #expect(request["enable_accelerate_text"] as? Bool == true)
        #expect(request["enable_ddc"] as? Bool == true)
        // "full" = cumulative transcript; "single" returned only the last VAD segment
        // and dropped every earlier sentence (2026-06-13 regression fix — openless parity).
        #expect(request["result_type"] as? String == "full")
        let score = try #require(request["accelerate_score"] as? Int)
        #expect(score >= 0 && score <= 20)
    }

    /// Placement is load-bearing: a live A/B (2026-06-11, 沈砚秋 clip) proved
    /// the server honors hotwords ONLY under `request.corpus.context` — the
    /// top-level `request.context` openless uses is silently ignored.
    @Test func firstFramePayloadInjectsHotwordContextUnderCorpus() throws {
        let data = VolcengineASRProtocol.firstFramePayload(
            connectID: "c", hotwords: [VolcengineHotword(phrase: "FSI", enabled: true)])
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let request = try #require(root["request"] as? [String: Any])
        #expect(request["context"] == nil)
        let corpus = try #require(request["corpus"] as? [String: Any])
        let context = try #require(corpus["context"] as? String)
        #expect(context.contains("FSI"))
    }

    /// An explicitly configured console 词表 wins and inline words are skipped —
    /// the doc gives 直传 priority over the table, so sending both would mute
    /// the user's 5 000-word table.
    @Test func corpusPrefersBoostingTableOverInlineWords() throws {
        let corpus = try #require(VolcengineASRProtocol.corpus(
            hotwords: [VolcengineHotword(phrase: "FSI", enabled: true)],
            boostingTableID: "tbl-123"))
        #expect(corpus["boosting_table_id"] as? String == "tbl-123")
        #expect(corpus["context"] == nil)

        // Blank table ID falls back to inline words.
        let inline = try #require(VolcengineASRProtocol.corpus(
            hotwords: [VolcengineHotword(phrase: "FSI", enabled: true)],
            boostingTableID: "  "))
        #expect((inline["context"] as? String)?.contains("FSI") == true)

        // Neither → nil (no corpus key at all).
        #expect(VolcengineASRProtocol.corpus(hotwords: [], boostingTableID: nil) == nil)
    }

    /// The nostream whole-clip path may carry far more inline words (doc:
    /// 5 000) — the cap parameter widens accordingly.
    @Test func corpusHonorsWiderNostreamCap() throws {
        let entries = (0..<600).map { VolcengineHotword(phrase: "w\($0)", enabled: true) }
        let corpus = try #require(VolcengineASRProtocol.corpus(
            hotwords: entries, cap: VolcengineASRProtocol.hotwordCapNostream))
        let context = try #require(corpus["context"] as? String)
        let object = try JSONSerialization.jsonObject(with: Data(context.utf8)) as? [String: Any]
        let words = try #require(object?["hotwords"] as? [[String: Any]])
        #expect(words.count == VolcengineASRProtocol.hotwordCapNostream)
    }

    // MARK: end_window_size per profile

    @Test func firstFramePayloadIncludesEndWindowSizeWhenProvided() throws {
        let vadConfig = VolcengineVADConfig(endWindowSize: 400, forceToSpeechTime: nil)
        let data = VolcengineASRProtocol.firstFramePayload(
            connectID: "c", hotwords: [], vadConfig: vadConfig)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let request = try #require(root["request"] as? [String: Any])
        #expect(request["end_window_size"] as? Int == 400)
        #expect(request["force_to_speech_time"] == nil)
    }

    @Test func firstFramePayloadIncludesForceToSpeechTimeForLegalProfile() throws {
        let vadConfig = VolcengineVADConfig(endWindowSize: 800, forceToSpeechTime: 1000)
        let data = VolcengineASRProtocol.firstFramePayload(
            connectID: "c", hotwords: [], vadConfig: vadConfig)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let request = try #require(root["request"] as? [String: Any])
        #expect(request["end_window_size"] as? Int == 800)
        #expect(request["force_to_speech_time"] as? Int == 1000)
    }

    @Test func firstFramePayloadOmitsEndWindowSizeWhenNilConfig() throws {
        let data = VolcengineASRProtocol.firstFramePayload(connectID: "c", hotwords: [])
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let request = try #require(root["request"] as? [String: Any])
        #expect(request["end_window_size"] == nil)
        #expect(request["force_to_speech_time"] == nil)
    }

    @Test func dictationProfileMapsToCorrectVolcengineVADConfig() {
        let quick = RealtimeDictationProfile.quickMessage.volcengineVADConfig
        #expect(quick?.endWindowSize == 400)
        #expect(quick?.forceToSpeechTime == nil)

        let legal = RealtimeDictationProfile.legalWriting.volcengineVADConfig
        #expect(legal?.endWindowSize == 800)
        #expect(legal?.forceToSpeechTime == 1000)

        let ptt = RealtimeDictationProfile.pushToTalk.volcengineVADConfig
        #expect(ptt == nil)

        let cmd = RealtimeDictationProfile.command.volcengineVADConfig
        #expect(cmd?.endWindowSize == 300)
    }

    // MARK: Server-result extraction

    @Test func transcriptTextReadsResultObjectText() {
        let json = Data(#"{"result":{"text":"hello world"}}"#.utf8)
        #expect(VolcengineASRProtocol.transcriptText(fromServerJSON: json) == "hello world")
    }

    @Test func transcriptTextReadsTopLevelText() {
        let json = Data(#"{"text":"top level"}"#.utf8)
        #expect(VolcengineASRProtocol.transcriptText(fromServerJSON: json) == "top level")
    }

    @Test func transcriptTextReadsFirstElementOfResultArray() {
        let json = Data(#"{"result":[{"text":"first"},{"text":"second"}]}"#.utf8)
        #expect(VolcengineASRProtocol.transcriptText(fromServerJSON: json) == "first")
    }

    /// Utterances are joined across ALL segments regardless of `definite` — the
    /// "definite=true is NOT stream end" rule: a fixed segment doesn't mean the
    /// user stopped, so we never drop later (non-definite) speech.
    @Test func transcriptTextJoinsAllUtterancesIgnoringDefinite() {
        let json = Data(#"""
        {"result":{"text":"你好","utterances":[
          {"text":"你好","definite":true},
          {"text":"世界","definite":false}
        ]}}
        """#.utf8)
        #expect(VolcengineASRProtocol.transcriptText(fromServerJSON: json) == "你好世界")
    }

    @Test func transcriptTextReturnsNilWhenNoResult() {
        let json = Data(#"{"code":0,"message":"ok"}"#.utf8)
        #expect(VolcengineASRProtocol.transcriptText(fromServerJSON: json) == nil)
    }
}
