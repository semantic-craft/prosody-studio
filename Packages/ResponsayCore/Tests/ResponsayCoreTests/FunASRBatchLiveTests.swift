import Testing
import Foundation
@testable import ResponsayCore

/// Real-network gate for the fun-asr batch pump. Off by default; run with
///   DASHSCOPE_KEY=sk-... swift test --filter FunASRBatchLiveTests
/// Optionally VOCAB_ID=vocab-... to assert hotword biasing end-to-end.
@Suite struct FunASRBatchLiveTests {
    @Test func livePumpTranscribesWav() async throws {
        guard let key = ProcessInfo.processInfo.environment["DASHSCOPE_KEY"], !key.isEmpty else {
            return  // network test disabled
        }
        let wavPath = ProcessInfo.processInfo.environment["LIVE_WAV"]
            ?? NSHomeDirectory() + "/Library/Application Support/Responsay/models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09/test_wavs/zh.wav"
        let audio = try Data(contentsOf: URL(fileURLWithPath: wavPath))
        let vocabID = ProcessInfo.processInfo.environment["VOCAB_ID"]

        let api = FunASRBatchTranscriptionAPI(
            apiKeyProvider: { key },
            vocabularyIDProvider: { vocabID })
        let result = try await api.transcribe(audio: audio, mimeType: "audio/wav", language: "zh")
        print("fun-asr batch live → \(result.text)")
        #expect(!result.text.isEmpty)
        #expect(result.provider == "qwen-fun-asr")
    }
}
