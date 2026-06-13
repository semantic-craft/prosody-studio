import Foundation

extension QuickCaptureViewModel {
    public enum Phase: Sendable, Equatable { case idle, listening, thinking, review, error }

    public enum OutputMode: Sendable, Equatable {
        case rawTranscript
        case polishedTranscript
        /// 重改写 (Heavy rewrite): same-language restructure via `/rewrite`, steered by a
        /// `RewriteTone`. Selection-driven (改写选中文本). Distinct from `.coachRewrite`,
        /// which switches to idiomatic English + teaching.
        case rewriteSameLanguage
        case coachRewrite
        case translate
        /// Snap-OCR translate (070/猎虫⑥ F1): translate card only, never inserts —
        /// a screenshot region has no insertion target.
        case translatePreview
        case analysisFeedback
        case teachingFeedback
        case practiceFeedback
        /// Legal palette (105): classify scene/stage and surface candidate skills
        /// instead of running the coach. Selection-driven; never inserts.
        case legalSuggest
        /// 语音划词追问: takes a selected text as context, listens for the user's voice
        /// question, and answers it inline.
        case askSelection
    }
}

extension QuickCaptureViewModel.OutputMode {
    /// Whether live ASR partials may be typed straight into the host field while
    /// listening. We keep this off for every mode: CGEvent-based partial replacement
    /// causes visible delete/retype jitter and cannot prove that cleanup really
    /// happened in the target app. Realtime engines still feed capsule preview; the
    /// host receives the final transcript once `stop()` returns.
    var streamsLiveTranscriptToHost: Bool {
        false
    }

    var speechCaptureProfile: SpeechCaptureProfile {
        switch self {
        case .polishedTranscript:
            .dictation
        case .rawTranscript, .rewriteSameLanguage, .coachRewrite, .translate, .translatePreview, .analysisFeedback, .teachingFeedback, .practiceFeedback, .legalSuggest, .askSelection:
            .faithful
        }
    }
}
