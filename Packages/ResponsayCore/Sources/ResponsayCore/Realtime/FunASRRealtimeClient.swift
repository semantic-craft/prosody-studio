import Foundation

/// Drives a Fun-ASR realtime streaming session over the DashScope generic task
/// protocol (`run-task` → binary PCM → `finish-task`). Unlike the retired Qwen
/// realtime client (OpenAI-realtime-compat framing, deleted in 289),
/// Fun-ASR sends audio as raw binary WebSocket frames and wraps
/// control messages in the `{header, payload}` task envelope.
///
/// Key differences from `qwen3-asr-flash-realtime`:
/// - Supports hotwords, word-level timestamps, speaker diarization
/// - Traditional ASR pipeline (Paraformer-based), not LLM-based
/// - Audio sent as binary frames, not base64-in-JSON
/// - Connection reuse supported (multiple tasks per WebSocket)
public actor FunASRRealtimeClient {
    private let transport: URLSessionWebSocketTask
    private let taskID: String

    private var finalTexts: [String] = []
    private var lastPartial = ""

    public init(transport: URLSessionWebSocketTask, taskID: String) {
        self.transport = transport
        self.taskID = taskID
    }

    // MARK: - Client → Server

    public func sendRunTask(endpoint: FunASRRealtimeEndpoint, vocabularyID: String? = nil) async throws {
        // Only parameters the server actually honors. The legacy NLS-style
        // switches (enable_intermediate_result / enable_punctuation_prediction /
        // enable_inverse_text_normalization / enable_words) and the inline
        // `vocabulary` array were proven inert by a live A/B on 2026-06-11:
        // bare parameters produce byte-identical output. Real hotwords use the
        // vocabulary_id resource flow (DashScopeVocabularyClient) — live-verified
        // to correct "response" → "Responsay" on fun-asr-realtime (issue 286).
        var parameters: [String: Any] = [
            "format": "pcm",
            "sample_rate": endpoint.sampleRate,
            // Documented keepalive: keeps the connection alive through long
            // silences (aliyun_realtime_asr.md recommends enabling it).
            "heartbeat": true,
        ]
        if let vocabularyID, !vocabularyID.isEmpty {
            parameters["vocabulary_id"] = vocabularyID
        }

        let payload: [String: Any] = [
            "header": [
                "action": "run-task",
                "task_id": taskID,
                "streaming": "duplex",
            ],
            "payload": [
                "task_group": "audio",
                "task": "asr",
                "function": "recognition",
                "model": endpoint.model,
                "parameters": parameters,
                "input": [String: Any](),
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try await transport.send(.string(String(data: data, encoding: .utf8)!))
    }

    public func sendAudio(_ pcm: Data) async throws {
        try await transport.send(.data(pcm))
    }

    public func sendFinishTask() async throws {
        let payload: [String: Any] = [
            "header": [
                "action": "finish-task",
                "task_id": taskID,
                "streaming": "duplex",
            ],
            "payload": [
                "input": [String: Any](),
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try await transport.send(.string(String(data: data, encoding: .utf8)!))
    }

    // MARK: - Server → Client

    public func receive() async throws -> FunASRServerEvent {
        let message = try await transport.receive()
        let data: Data
        switch message {
        case let .string(text):
            data = Data(text.utf8)
        case let .data(d):
            data = d
        @unknown default:
            return .unknown
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let header = root["header"] as? [String: Any],
              let event = header["event"] as? String else {
            return .unknown
        }

        switch event {
        case "task-started":
            return .taskStarted
        case "result-generated":
            return parseResult(root)
        case "task-finished":
            return .taskFinished
        case "task-failed":
            let code = header["error_code"] as? String ?? ""
            let message = header["error_message"] as? String ?? ""
            return .taskFailed(code: code, message: message)
        default:
            return .unknown
        }
    }

    private func parseResult(_ root: [String: Any]) -> FunASRServerEvent {
        guard let payload = root["payload"] as? [String: Any],
              let output = payload["output"] as? [String: Any],
              let sentence = output["sentence"] as? [String: Any] else {
            return .unknown
        }
        let text = sentence["text"] as? String ?? ""
        let sentenceEnd = sentence["sentence_end"] as? Bool ?? false
        let heartbeat = sentence["heartbeat"] as? Bool ?? false
        let sentenceID = sentence["sentence_id"] as? Int ?? 0

        if heartbeat { return .heartbeat }

        var words: [FunASRWord] = []
        if let wordArray = sentence["words"] as? [[String: Any]] {
            words = wordArray.map { w in
                FunASRWord(
                    text: w["text"] as? String ?? "",
                    beginTime: w["begin_time"] as? Int ?? 0,
                    endTime: w["end_time"] as? Int ?? 0,
                    punctuation: w["punctuation"] as? String ?? "")
            }
        }

        return .result(FunASRResult(
            text: text,
            sentenceEnd: sentenceEnd,
            sentenceID: sentenceID,
            beginTime: sentence["begin_time"] as? Int ?? 0,
            endTime: sentence["end_time"] as? Int ?? 0,
            words: words))
    }

    // MARK: - State management

    public func handleEvent(_ event: FunASRServerEvent) -> TranscriptUpdate? {
        switch event {
        case .taskStarted, .heartbeat, .unknown:
            return nil
        case let .result(result):
            if result.sentenceEnd {
                let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { finalTexts.append(trimmed) }
                lastPartial = ""
                return .final(transcript: TranscriptJoiner.join(finalTexts))
            } else {
                lastPartial = result.text
                let preview = TranscriptJoiner.join(finalTexts + [result.text])
                return .partial(preview: preview)
            }
        case .taskFinished:
            return nil
        case let .taskFailed(_, message):
            return .failed(message: message)
        }
    }

    public var transcript: String {
        let trimmedPartial = lastPartial.trimmingCharacters(in: .whitespacesAndNewlines)
        if finalTexts.isEmpty && trimmedPartial.isEmpty { return "" }
        if trimmedPartial.isEmpty { return TranscriptJoiner.join(finalTexts) }
        return TranscriptJoiner.join(finalTexts + [trimmedPartial])
    }
}

// MARK: - Protocol types

public enum FunASRServerEvent: Sendable {
    case taskStarted
    case result(FunASRResult)
    case taskFinished
    case taskFailed(code: String, message: String)
    case heartbeat
    case unknown
}

public struct FunASRResult: Sendable, Equatable {
    public let text: String
    public let sentenceEnd: Bool
    public let sentenceID: Int
    public let beginTime: Int
    public let endTime: Int
    public let words: [FunASRWord]
}

public struct FunASRWord: Sendable, Equatable {
    public let text: String
    public let beginTime: Int
    public let endTime: Int
    public let punctuation: String
}
