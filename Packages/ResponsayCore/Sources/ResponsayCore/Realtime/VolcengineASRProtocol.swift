import Foundation

/// Credentials for the Volcengine (火山引擎) 大模型流式 ASR service. APP ID +
/// Access Token come from the console's "豆包流式语音识别模型 2.0" page
/// (<https://console.volcengine.com/speech/service/10038>); the Secret Key is
/// not used for this product. Resource ID defaults to `volc.seedasr.sauc.duration`.
public struct VolcengineCredentials: Sendable, Equatable {
    public var appId: String
    public var accessToken: String
    public var resourceID: String

    /// The SAUC bigmodel "小时版" (hourly) resource id; the only one this client targets.
    public static let defaultResourceID = "volc.seedasr.sauc.duration"

    /// Streaming endpoint for the "豆包流式语音识别模型 2.0" product (console
    /// service/10038). Single source of truth — the macOS provider catalog
    /// references this constant rather than re-typing the URL.
    public static let streamingEndpoint = "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async"

    public init(appId: String, accessToken: String, resourceID: String = defaultResourceID) {
        self.appId = appId
        self.accessToken = accessToken
        self.resourceID = resourceID
    }

    public var isComplete: Bool {
        !appId.trimmed.isEmpty && !accessToken.trimmed.isEmpty && !resourceID.trimmed.isEmpty
    }
}

/// A user-defined hotword the ASR provider may use to bias decoding.
public struct VolcengineHotword: Sendable, Equatable {
    public var phrase: String
    public var enabled: Bool

    public init(phrase: String, enabled: Bool) {
        self.phrase = phrase
        self.enabled = enabled
    }
}

/// Failures surfaced by the streaming client. `authRejected` is split out from
/// `connectionFailed` so the UI can tell "凭据被拒 (401/403 — App ID / Access
/// Token / Resource ID 错或没开通)" apart from a network/DNS/TLS failure.
public enum VolcengineASRError: Error, Equatable, LocalizedError {
    case credentialsMissing
    case connectionFailed(String)
    case authRejected(Int)
    case noFinalResult
    case finalResultTimeout
    case decodeFailed(String)
    case asrError(code: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .credentialsMissing:
            return "请先在设置中填写豆包语音 ASR 的 API Key。"
        case let .connectionFailed(detail):
            return "豆包语音 ASR 连接失败：\(detail)"
        case let .authRejected(status):
            return "豆包语音凭据被拒（HTTP \(status)）。请检查 API Key / Model (Resource ID)，以及账号是否已开通大模型流式识别。"
        case .noFinalResult:
            return "豆包语音 ASR 未返回最终结果。"
        case .finalResultTimeout:
            return "豆包语音 ASR 等待最终结果超时。"
        case let .decodeFailed(detail):
            return "豆包语音 ASR 解码失败：\(detail)"
        case let .asrError(code, message):
            return "豆包语音 ASR 错误 \(code): \(message)"
        }
    }
}

/// Volcengine server-side VAD tuning knobs passed in the first-frame `request`.
public struct VolcengineVADConfig: Sendable, Equatable {
    public var endWindowSize: Int
    public var forceToSpeechTime: Int?

    public init(endWindowSize: Int, forceToSpeechTime: Int? = nil) {
        self.endWindowSize = endWindowSize
        self.forceToSpeechTime = forceToSpeechTime
    }
}

/// Pure (socket-free) helpers for the SAUC bigmodel wire protocol — fully unit
/// tested. The streaming session lifecycle lives in `VolcengineStreamingASRClient`.
enum VolcengineASRProtocol {
    /// Endpoint for the streaming "豆包流式语音识别模型 2.0" product (service/10038);
    /// the *streaming* `sauc/bigmodel_async` path, distinct from batch 录音识别
    /// `auc/bigmodel`. The single source of truth is `VolcengineCredentials`.
    static let endpoint = VolcengineCredentials.streamingEndpoint

    /// 200 ms of 16 kHz / 16-bit / mono PCM.
    static let targetAudioChunkBytes = 6_400
    /// Most distinct hotwords sent in the `corpus.context` blob. The
    /// bidirectional streaming endpoints only honor ~100 *tokens* of inline
    /// hotwords (volcengine_asr.md「热词」节) — at ~4 tokens per CJK/term
    /// phrase, 24 phrases stays inside that budget; the old cap of 80
    /// phrases silently overflowed it.
    static let hotwordCap = 24
    /// The nostream (whole-clip) endpoint honors up to 5 000 inline words
    /// (volcengine_asr.md:481 「流式输入nostream支持5000个词」); 500 is a
    /// defensive ceiling far above any personal-dictionary size.
    static let hotwordCapNostream = 500

    /// Build the `context` JSON string biasing decoding toward the enabled hotwords,
    /// or `nil` when there are none. De-duplicates case-insensitively, drops blanks
    /// and disabled entries, and caps at `hotwordCap` distinct phrases.
    static func hotwordContext(_ entries: [VolcengineHotword], cap: Int = hotwordCap) -> String? {
        var seen: [String] = []
        for entry in entries {
            guard entry.enabled else { continue }
            let trimmed = entry.phrase.trimmed
            guard !trimmed.isEmpty else { continue }
            if seen.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) { continue }
            seen.append(trimmed)
            if seen.count >= cap { break }
        }
        guard !seen.isEmpty else { return nil }
        let words = seen.map { ["word": $0] }
        guard let data = try? JSONSerialization.data(withJSONObject: ["hotwords": words]),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    /// The optional `request.corpus` dict carrying hotword biasing. Placement
    /// matters: the official doc (volcengine_asr.md:476-481) nests both fields
    /// under `corpus`, and a live A/B (2026-06-11, 沈砚秋 clip) proved the
    /// top-level `request.context` we ported from openless is silently
    /// ignored — `corpus.context` flips 沈艳秋→沈砚秋, top-level does not.
    /// A console-managed 词表 (`boosting_table_id`, 5 000 words + weights)
    /// and inline 直传 are mutually exclusive per request: the doc gives 直传
    /// priority, so sending both would mute the table — an explicitly
    /// configured table ID therefore wins and inline words are skipped.
    static func corpus(
        hotwords: [VolcengineHotword],
        boostingTableID: String? = nil,
        cap: Int = hotwordCap
    ) -> [String: Any]? {
        if let tableID = boostingTableID?.trimmed, !tableID.isEmpty {
            return ["boosting_table_id": tableID]
        }
        if let context = hotwordContext(hotwords, cap: cap) {
            return ["context": context]
        }
        return nil
    }

    /// The `FullClientRequest` JSON payload (seq=1): declares the audio format and
    /// decoding options, plus the optional hotword `corpus`.
    static let defaultAccelerateScore = 12

    static func firstFramePayload(
        connectID: String,
        hotwords: [VolcengineHotword],
        boostingTableID: String? = nil,
        vadConfig: VolcengineVADConfig? = nil
    ) -> Data {
        var request: [String: Any] = [
            "model_name": "bigmodel",
            "enable_itn": true,
            "enable_punc": true,
            "show_utterances": true,
            "enable_accelerate_text": true,
            "accelerate_score": defaultAccelerateScore,
            "enable_ddc": true,
            // MUST be "full" (cumulative), NOT "single". With "single" the server
            // returns only the CURRENT VAD segment per frame, so after it splits a
            // multi-sentence utterance the final frame holds only the LAST segment —
            // every earlier sentence is dropped, and a trailing-silence last segment
            // yields an empty final (live-verified 2026-06-13: 16 s speech → 12 chars;
            // 6 s → 0 chars). "full" returns the whole accumulated transcript, which is
            // what `transcriptText`/the capsule expect. openless omits the field and
            // relies on the same cumulative default. Do not change back to "single".
            "result_type": "full",
        ]
        if let corpus = corpus(hotwords: hotwords, boostingTableID: boostingTableID) {
            request["corpus"] = corpus
        }
        if let vad = vadConfig {
            request["end_window_size"] = vad.endWindowSize
            if let force = vad.forceToSpeechTime {
                request["force_to_speech_time"] = force
            }
        }
        let payload: [String: Any] = [
            "user": ["uid": connectID],
            "audio": [
                "format": "pcm",
                "rate": 16_000,
                "bits": 16,
                "channel": 1,
                "codec": "raw",
            ],
            "request": request,
        ]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    /// Best-effort assembled transcript from a `FullServerResponse` JSON payload, or
    /// `nil` when there is no result. Prefers joining ALL `utterances` (every segment,
    /// definite or not) over the top-level `text` so a fixed segment never drops the
    /// trailing, still-streaming speech.
    static func transcriptText(fromServerJSON data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data),
              let result = normalizedResult(root) else {
            return nil
        }
        var text = (result["text"] as? String) ?? ""
        if let utterances = result["utterances"] as? [[String: Any]] {
            let pieces = utterances.compactMap { $0["text"] as? String }
            if !pieces.isEmpty {
                text = TranscriptJoiner.join(pieces)
            }
        }
        return text
    }

    private static func normalizedResult(_ json: Any) -> [String: Any]? {
        guard let object = json as? [String: Any] else { return nil }
        if let result = object["result"] {
            if let resultObject = result as? [String: Any] { return resultObject }
            if let array = result as? [[String: Any]], let first = array.first { return first }
        }
        if object["text"] is String { return object }
        return nil
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
