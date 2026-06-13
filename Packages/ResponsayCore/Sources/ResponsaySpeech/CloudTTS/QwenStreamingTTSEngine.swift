import Foundation
import ResponsayCore

/// One decoded frame from the Qwen realtime TTS WebSocket (issue 197).
enum QwenTTSStreamEvent: Equatable {
    case audio(Data)       // base64-decoded 24 kHz mono 16-bit PCM segment
    case done              // response.done / session.finished
    case failure(String)   // error event
    case ignored           // session.created / .updated / unknown — informational
}

/// Pure framing for the DashScope realtime TTS protocol (server_commit mode),
/// faithful to the verified `ai-voice-studio/qwen-tts-realtime.ts`:
///   session.update → input_text_buffer.append → session.finish, then a stream of
///   `response.audio.delta` (base64 PCM) ending on `response.done`/`session.finished`.
/// No socket here, so it's fully headless-testable.
enum QwenTTSStreamDecoder {
    static func decode(_ frame: Data) -> QwenTTSStreamEvent {
        guard let obj = try? JSONSerialization.jsonObject(with: frame) as? [String: Any] else {
            return .ignored
        }
        switch obj["type"] as? String {
        case "response.audio.delta":
            let seg = (obj["delta"] as? String) ?? (obj["audio"] as? String)
            if let seg, let data = Data(base64Encoded: seg), !data.isEmpty { return .audio(data) }
            return .ignored
        case "response.done", "session.finished":
            return .done
        case "error":
            let msg = (obj["error"] as? [String: Any])?["message"] as? String
                ?? obj["message"] as? String ?? "通义千问实时语音错误"
            return .failure(msg)
        default:
            return .ignored
        }
    }

    static func sessionUpdate(voice: String, instructions: String?) -> Data {
        var session: [String: Any] = ["voice": voice, "response_format": "pcm", "mode": "server_commit"]
        if let instructions, !instructions.isEmpty { session["instructions"] = instructions }
        return json(["type": "session.update", "session": session])
    }

    static func inputTextAppend(_ text: String) -> Data {
        json(["type": "input_text_buffer.append", "text": text])
    }

    static func sessionFinish() -> Data { json(["type": "session.finish"]) }

    private static func json(_ obj: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    }
}

/// BYOK direct streaming TTS over the Qwen realtime WebSocket (issue 197) — low
/// TTFB for cloud read-aloud. Reuses the realtime ASR transport
/// (`URLSessionWebSocketTaskTransport`) + endpoint; key from the Keychain.
public struct QwenStreamingTTSEngine: StreamingSpeechSynthesizer {
    let key: String
    var model = "qwen3-tts-flash-realtime"
    var voice = "Cherry"
    var region: QwenRealtimeRegion = .china
    var instructions: String?

    public init(key: String, model: String = "qwen3-tts-flash-realtime", voice: String = "Cherry",
                region: QwenRealtimeRegion = .china, instructions: String? = nil) {
        self.key = key
        self.model = model
        self.voice = voice
        self.region = region
        self.instructions = instructions
    }

    public func stream(_ text: String, speed: Double) -> AsyncThrowingStream<SynthesizedSpeech, Error> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.chunks(from: liveFrames(trimmed))
    }

    /// Pure assembler (testable): map ordered WS frames → ordered audio chunks,
    /// finishing on `done` and throwing on `failure`.
    static func chunks(
        from frames: AsyncThrowingStream<Data, Error>
    ) -> AsyncThrowingStream<SynthesizedSpeech, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await frame in frames {
                        switch QwenTTSStreamDecoder.decode(frame) {
                        case .audio(let data):
                            continuation.yield(try CloudTTSAudioDecoder.pcm16(data, sampleRate: TTSAudio.defaultSampleRate))
                        case .done:
                            continuation.finish(); return
                        case .failure(let message):
                            continuation.finish(throwing: TTSError.synthesisFailed(message)); return
                        case .ignored:
                            continue
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Connect the WebSocket, kick off synthesis, and surface raw frames.
    private func liveFrames(_ text: String) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            guard !text.isEmpty else { continuation.finish(throwing: TTSError.emptyText); return }
            guard !key.isEmpty else {
                continuation.finish(throwing: TTSError.missingAPIKey(provider: "通义千问"))
                return
            }
            let transport = URLSessionWebSocketTaskTransport()
            let endpoint = QwenRealtimeEndpoint(model: model, region: region)
            let voice = voice
            let instructions = instructions
            let task = Task {
                do {
                    await transport.connect(endpoint: endpoint, bearerToken: key)
                    try await transport.send(QwenTTSStreamDecoder.sessionUpdate(voice: voice, instructions: instructions))
                    try await transport.send(QwenTTSStreamDecoder.inputTextAppend(text))
                    try await transport.send(QwenTTSStreamDecoder.sessionFinish())
                    while !Task.isCancelled {
                        continuation.yield(try await transport.receive())
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                await transport.disconnect()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
