import XCTest
@testable import ResponsayCore

/// Env-gated LIVE test of the real `VolcengineStreamingASRClient` against the
/// production endpoint — the Swift-path counterpart of
/// `scripts/volc-auth-matrix-smoke.mjs`. Skips (never fails) without real
/// credentials, so the default suite stays green offline.
///
///   VOLC_APP_ID=… VOLC_ACCESS_TOKEN=… [VOLC_LIVE_WAV=/path.wav] \
///     swift test --filter VolcengineConnectionTest
///
/// History: until 2026-06-11 this test hard-coded fake credentials and thus
/// failed unconditionally — a permanently-red test the green-suite claims
/// missed because XCTest and Swift Testing print separate summaries.
final class VolcengineConnectionTest: XCTestCase {
    func testLiveStreamingWithCorpusHotwords() async throws {
        guard let appId = ProcessInfo.processInfo.environment["VOLC_APP_ID"],
              let token = ProcessInfo.processInfo.environment["VOLC_ACCESS_TOKEN"] else {
            throw XCTSkip("VOLC_APP_ID / VOLC_ACCESS_TOKEN not set — live test skipped")
        }

        let wavPath = ProcessInfo.processInfo.environment["VOLC_LIVE_WAV"]
            ?? NSHomeDirectory() + "/Library/Application Support/Responsay/models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09/test_wavs/zh.wav"
        let wav = try Data(contentsOf: URL(fileURLWithPath: wavPath))
        let pcm = FunASRBatchTranscriptionAPI.pcmPayload(from: wav, mimeType: "audio/wav")

        let client = VolcengineStreamingASRClient(
            credentials: VolcengineCredentials(appId: appId, accessToken: token),
            hotwords: [VolcengineHotword(phrase: "沈砚秋", enabled: true)])

        try await client.openSession()
        var offset = 0
        let chunk = VolcengineASRProtocol.targetAudioChunkBytes
        while offset < pcm.count {
            await client.consume(pcm: pcm.subdata(in: offset..<min(offset + chunk, pcm.count)))
            offset += chunk
        }
        try await client.sendLastFrame()
        let transcript = try await client.awaitFinalResult()
        XCTAssertFalse(transcript.isEmpty, "live transcript should not be empty")
        print("=== LIVE transcript: \(transcript) ===")
    }
}
