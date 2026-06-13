import Foundation
import OSLog
import ResponsayCore
import ResponsaySpeech

// Phase 3 shims — minimal app-level glue so the migrated screens / ReadAloudController
// build and the app launches. The real implementations in responsay pull deep chains
// (sherpa-onnx native TTS, BYOK credential routing, the diagnostics panel); the
// prosody-studio fluent-based redesign will wire its own. Until then these keep the
// surface compiling with graceful no-ops.

// MARK: - Diag (→ OSLog; descriptors only, never raw user text)

enum Diag {
    enum Level { case info, error, warning, debug }
    private static let log = Logger(subsystem: "com.semanticcraft.prosodystudio", category: "diag")
    static func tts(_ level: Level, _ title: String,
                    fields: [String: String] = [:], error: String? = nil) {
        log.debug("[tts] \(title, privacy: .public)")
    }
}

// MARK: - TTSEngine (stub; ReadAloudController degrades to an estimated timeline
// on synth failure, so the UI never breaks without real audio)

enum TTSEngine: CaseIterable {
    case stub
    static var selected: TTSEngine { .stub }
    var title: String { "TTS（待接入）" }
    func makeSynthesizer() throws -> any SpeechSynthesizer { StudioTTSStub() }
    func makeStreamingSynthesizer() throws -> (any StreamingSpeechSynthesizer)? { nil }
}

private struct StudioTTSStub: SpeechSynthesizer {
    func synthesize(_ text: String, speed: Double) async throws -> SynthesizedSpeech {
        throw TTSError.synthesisFailed("prosody-studio 的 TTS 引擎将在 fluent 重设计时接入")
    }
}
