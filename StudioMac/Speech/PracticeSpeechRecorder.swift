import AVFoundation
import Foundation

struct PracticeRecordingResult {
    let text: String
    let audioFileURL: URL
}

/// Phase 3 shim: records mic audio locally for shadowing; transcription is stubbed
/// (the real BYOK ASR + hotword chain lives in responsay). The fluent-based redesign
/// will wire prosody-studio's own recognizer so the comparison feedback comes alive.
@MainActor
final class PracticeSpeechRecorder {
    private var recorder: AVAudioRecorder?
    private var fileURL: URL?

    func start(maxDuration: TimeInterval = 20) throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("caf")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let rec = try AVAudioRecorder(url: url, settings: settings)
        rec.record(forDuration: maxDuration)
        recorder = rec
        fileURL = url
    }

    func stopAndTranscribeKeepingAudio(language: String = "en") async throws -> PracticeRecordingResult {
        recorder?.stop()
        let url = fileURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("caf")
        recorder = nil
        fileURL = nil
        return PracticeRecordingResult(text: "", audioFileURL: url)
    }

    func cleanupAudio(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    func cancel() {
        recorder?.stop()
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        recorder = nil
        fileURL = nil
    }
}
