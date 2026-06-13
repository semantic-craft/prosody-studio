import Foundation
import ResponsayCore

/// One decoded event from MiMo's OpenAI-compatible streaming TTS response.
enum MiMoTTSStreamEvent: Equatable {
    case audio(Data)       // base64-decoded 24 kHz mono PCM16LE segment
    case done              // [DONE] / finish_reason
    case failure(String)   // provider error object
    case ignored           // keep-alive / metadata / unknown chunk
}

/// Pure decoder for MiMo `mimo-v2.5-tts` streaming TTS.
enum MiMoTTSStreamDecoder {
    static func requestBody(text: String, model: String, voice: String) -> [String: Any] {
        [
            "model": model,
            "messages": [["role": "assistant", "content": text]],
            "audio": ["format": "pcm16", "voice": voice],
            "stream": true,
        ]
    }

    static func eventData(from line: String) -> Data? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix(":") else { return nil }
        if trimmed.hasPrefix("data:") {
            let payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            return payload.isEmpty ? nil : Data(payload.utf8)
        }
        if trimmed == "[DONE]" || trimmed.hasPrefix("{") {
            return Data(trimmed.utf8)
        }
        return nil
    }

    static func decode(_ eventData: Data) -> MiMoTTSStreamEvent {
        if String(data: eventData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
            return .done
        }
        guard let obj = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any] else {
            return .ignored
        }
        if let error = obj["error"] as? [String: Any] {
            return .failure(error["message"] as? String ?? "MiMo 语音合成错误")
        }
        guard let choices = obj["choices"] as? [[String: Any]] else { return .ignored }
        var sawFinish = false
        for choice in choices {
            if let delta = choice["delta"] as? [String: Any],
               let audio = delta["audio"] as? [String: Any],
               let b64 = audio["data"] as? String,
               let data = Data(base64Encoded: b64),
               !data.isEmpty {
                return .audio(data)
            }
            if choice["finish_reason"] is String { sawFinish = true }
        }
        return sawFinish ? .done : .ignored
    }

    static func collectPCM16(fromEventStream data: Data) throws -> Data? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        var collected = Data()
        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            guard let event = eventData(from: line) else { continue }
            switch decode(event) {
            case .audio(let chunk):
                collected.append(chunk)
            case .done:
                return collected.isEmpty ? nil : collected
            case .failure(let message):
                throw TTSError.synthesisFailed(message)
            case .ignored:
                continue
            }
        }
        return collected.isEmpty ? nil : collected
    }
}

/// BYOK direct streaming TTS over MiMo's OpenAI-compatible chat-completions SSE API.
public struct MiMoStreamingTTSEngine: StreamingSpeechSynthesizer {
    let key: String
    public var baseURL = URL(string: "https://api.xiaomimimo.com/v1")!
    var model = "mimo-v2.5-tts"
    var voice = "Chloe"
    var session: URLSession = .shared

    public init(key: String, model: String = "mimo-v2.5-tts", voice: String = "Chloe",
                baseURL: URL = URL(string: "https://api.xiaomimimo.com/v1")!,
                session: URLSession = .shared) {
        self.key = key
        self.model = model
        self.voice = voice
        self.baseURL = baseURL
        self.session = session
    }

    public func stream(_ text: String, speed: Double) -> AsyncThrowingStream<SynthesizedSpeech, Error> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.chunks(from: liveEvents(trimmed))
    }

    static func chunks(
        from events: AsyncThrowingStream<Data, Error>
    ) -> AsyncThrowingStream<SynthesizedSpeech, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in events {
                        switch MiMoTTSStreamDecoder.decode(event) {
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

    private func liveEvents(_ text: String) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            guard !text.isEmpty else { continuation.finish(throwing: TTSError.emptyText); return }
            guard !key.isEmpty else {
                continuation.finish(throwing: TTSError.missingAPIKey(provider: "小米 MIMO"))
                return
            }
            let request: URLRequest
            do {
                request = try makeRequest(text)
            } catch {
                continuation.finish(throwing: error)
                return
            }
            let session = session
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: TTSError.network("无 HTTP 响应"))
                        return
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        continuation.finish(throwing: TTSError.http(status: http.statusCode))
                        return
                    }
                    for try await line in bytes.lines {
                        if let event = MiMoTTSStreamDecoder.eventData(from: line) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: TTSError.network(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeRequest(_ text: String) throws -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue(key, forHTTPHeaderField: "api-key")
        req.httpBody = try JSONSerialization.data(
            withJSONObject: MiMoTTSStreamDecoder.requestBody(text: text, model: model, voice: voice))
        return req
    }
}
