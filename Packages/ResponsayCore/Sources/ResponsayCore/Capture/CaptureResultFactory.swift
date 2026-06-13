import Foundation

enum CaptureResultFactory {
    static func raw(_ text: String) -> CaptureResult {
        CaptureResult(
            mode: .raw,
            sourceTranscript: text,
            insertText: text,
            outputLanguage: .source,
            transformKind: .none,
            insertPolicy: .insertImmediately,
            sidecarPolicy: .collapsed)
    }

    static func rawCopyOnly(_ text: String) -> CaptureResult {
        CaptureResult(
            mode: .raw,
            sourceTranscript: text,
            insertText: text,
            outputLanguage: .source,
            transformKind: .none,
            insertPolicy: .copyOnly,
            sidecarPolicy: .collapsed)
    }

    static func polish(source: String, output: String) -> CaptureResult {
        CaptureResult(
            mode: .polishSameLanguage,
            sourceTranscript: source,
            insertText: output,
            outputLanguage: .source,
            transformKind: .sameLanguagePolish,
            insertPolicy: .insertImmediately,
            sidecarPolicy: .badgeOnly)
    }

    /// 重改写 on a selection: same-language restructure that replaces the selected text.
    static func rewriteSelection(source: String, output: String) -> CaptureResult {
        CaptureResult(
            mode: .rewriteSelection,
            sourceTranscript: source,
            insertText: output,
            outputLanguage: .source,
            transformKind: .sameLanguagePolish,
            insertPolicy: .replaceSelection,
            sidecarPolicy: .badgeOnly)
    }

    static func translateSelection(source: String, output: String) -> CaptureResult {
        CaptureResult(
            mode: .translateSelection,
            sourceTranscript: source,
            insertText: output,
            outputLanguage: .target,
            transformKind: .translateSelection,
            insertPolicy: .replaceSelection,
            sidecarPolicy: .collapsed)
    }

    /// Snap-OCR translate (070): the same card as `translateSelection`, but it
    /// NEVER inserts — a screenshot region has no meaningful insertion target;
    /// auto-inserting pasted the translation into whichever app the target
    /// tracker captured LAST (猎虫⑥ F1). 070's acceptance is "capsule result
    /// card", not a paste.
    static func translatePreview(source: String, output: String) -> CaptureResult {
        CaptureResult(
            mode: .translateSelection,
            sourceTranscript: source,
            insertText: output,
            outputLanguage: .target,
            transformKind: .translateSelection,
            insertPolicy: .noInsert,
            sidecarPolicy: .collapsed)
    }

    static func coach(source: String, card: ExpressionResult) -> CaptureResult {
        CaptureResult(
            mode: .coach,
            sourceTranscript: source,
            insertText: nil,
            outputLanguage: .englishWithChineseCoach,
            transformKind: .coachOnly,
            insertPolicy: .noInsert,
            sidecarPolicy: .autoOpenCoach,
            coachCard: card)
    }

    static func analysis(source: String, card: ExpressionResult, prosody: ProsodyAnalysis) -> CaptureResult {
        CaptureResult(
            mode: .analysis,
            sourceTranscript: source,
            insertText: nil,
            outputLanguage: .englishWithChineseCoach,
            transformKind: .prosodyOnly,
            insertPolicy: .noInsert,
            sidecarPolicy: .autoOpenProsody,
            coachCard: card,
            prosodyAnalysis: prosody)
    }

    static func expressInEnglish(
        source: String,
        insertText: String,
        coachCard: ExpressionResult,
        prosody: ProsodyAnalysis? = nil
    ) -> CaptureResult {
        CaptureResult(
            mode: .expressInEnglish,
            sourceTranscript: source,
            insertText: insertText,
            outputLanguage: .english,
            transformKind: .intentToEnglish,
            insertPolicy: .insertImmediately,
            sidecarPolicy: .autoOpenCoach,
            coachCard: coachCard,
            prosodyAnalysis: prosody)
    }

    static func practice(source: String, card: ExpressionResult, prosody: ProsodyAnalysis) -> CaptureResult {
        CaptureResult(
            mode: .practice,
            sourceTranscript: source,
            insertText: nil,
            outputLanguage: .englishWithChineseCoach,
            transformKind: .practiceSeed,
            insertPolicy: .noInsert,
            sidecarPolicy: .autoOpenPractice,
            coachCard: card,
            prosodyAnalysis: prosody)
    }
}
