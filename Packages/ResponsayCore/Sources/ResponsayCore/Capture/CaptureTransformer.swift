import Foundation

// MARK: - 375 TextTransformOutcome + CaptureTransformer
//
// The transform "substantial logic" lifted off QuickCaptureViewModel: the
// streaming-vs-API branch and the CaptureResult / persistence intent for raw /
// polish / rewrite / translate / express. The transformer owns the DECISIONS and
// returns a `TextTransformOutcome` descriptor; the VM's `apply(_:)` is the only
// place that mutates @Observable state (#372 sibling — like LegalCaptureCoordinator).
//
// Behaviour is preserved 1:1 from the former `+TextTransforms` methods, including
// the per-case `language` tags (note: translate *streamed* historically tags the
// item with `locale`, while translate *failed/api* tags it `translate:<target>`).

/// What the view model should do after a transform. Computed by `CaptureTransformer`,
/// applied by `QuickCaptureViewModel.apply(_:)`.
public enum TextTransformOutcome: Sendable {
    /// Build `capture`, the VM inserts it (insertIfNeeded) and persists `item`; phase → .idle.
    case insert(capture: CaptureResult, item: CaptureItem)
    /// Streaming already wrote to the host; set `capture`, persist `item`; phase → .idle.
    case streamed(capture: CaptureResult, item: CaptureItem)
    /// Coach result → review: set `result` + `capture`, persist `item`; phase → .review.
    case review(result: ExpressionResult, capture: CaptureResult, item: CaptureItem)
    /// Coach result already streamed in: set `result` + `capture`, persist; phase → .idle.
    case streamedResult(result: ExpressionResult, capture: CaptureResult, item: CaptureItem)
    /// Failure: optionally set `capture`/`result` + persist `item`, then enter error.
    case failed(reason: String, capture: CaptureResult?, result: ExpressionResult?, item: CaptureItem?)
    /// Teaching stage 2: the express text was already auto-inserted, now enriched
    /// with prosody → review. Sets `result` + `capture`(+prosody), persists `item`,
    /// marks `didAutoInsertResult`, phase → .review.
    case autoInsertedReview(result: ExpressionResult, capture: CaptureResult, item: CaptureItem)
}

/// Result of the teaching/express stage 1 (express → immediate insert). The VM
/// applies each case (the API path then runs the analyze stage). Distinct from the
/// 5-transform `TextTransformOutcome` because teaching auto-inserts (no review gate)
/// and stages an insert *before* the slow prosody analyze.
public enum TeachingExpressStage: Sendable {
    /// Streaming already wrote the idiomatic to the host: set `capture`, mark
    /// auto-inserted, no persistence, phase → .idle.
    case streamed(capture: CaptureResult)
    /// Streaming failed; a non-empty partial is carried in `capture`/`item`
    /// (persist + mark auto-inserted), then enter error.
    case streamedFailed(reason: String, capture: CaptureResult?, item: CaptureItem?)
    /// API express succeeded: the VM inserts `capture` now, marks auto-inserted,
    /// then runs `teachingAnalyze` for the prosody enrich.
    case expressed(idiomatic: String, exprReasons: [String], capture: CaptureResult)
    /// Express itself failed → just enter error (nothing inserted/persisted).
    case failed(reason: String)
}

@MainActor
public final class CaptureTransformer {
    private let streamingInsert: (@MainActor (_ transcript: String, _ mode: String, _ targetLanguage: String?) async -> StreamingTransformOutcome)?
    private let polisher: (any TextPolishAPI)?
    private let rewriter: (any TextRewriteAPI)?
    private let translator: (any TextTranslationAPI)?
    private let contextProvider: (@MainActor () -> ExpressionContext?)?
    private let translationTargetProvider: (@MainActor () -> TranslationTargetLanguage)?
    private let rewriteToneProvider: (@MainActor () -> RewriteTone)?
    private let rewriteStyleProvider: (@MainActor () -> RewriteStyle)?

    public init(
        streamingInsert: (@MainActor (_ transcript: String, _ mode: String, _ targetLanguage: String?) async -> StreamingTransformOutcome)?,
        polisher: (any TextPolishAPI)?,
        rewriter: (any TextRewriteAPI)?,
        translator: (any TextTranslationAPI)?,
        contextProvider: (@MainActor () -> ExpressionContext?)?,
        translationTargetProvider: (@MainActor () -> TranslationTargetLanguage)?,
        rewriteToneProvider: (@MainActor () -> RewriteTone)?,
        rewriteStyleProvider: (@MainActor () -> RewriteStyle)?
    ) {
        self.streamingInsert = streamingInsert
        self.polisher = polisher
        self.rewriter = rewriter
        self.translator = translator
        self.contextProvider = contextProvider
        self.translationTargetProvider = translationTargetProvider
        self.rewriteToneProvider = rewriteToneProvider
        self.rewriteStyleProvider = rewriteStyleProvider
    }

    // MARK: - Transforms (assume non-empty input; the VM guards empty + sets transcript)

    public func raw(_ text: String, locale: CaptureLocale) -> TextTransformOutcome {
        .insert(
            capture: CaptureResultFactory.raw(text),
            item: item(source: text, language: locale.rawValue, output: text, reasons: []))
    }

    public func polish(_ text: String, locale: CaptureLocale) async -> TextTransformOutcome {
        if let streamingInsert {
            switch await streamingInsert(text, "polish", nil) {
            case let .streamed(inserted):
                return .streamed(
                    capture: CaptureResultFactory.polish(source: text, output: inserted),
                    item: item(source: text, language: locale.rawValue, output: inserted, reasons: []))
            case .unsupportedFallback:
                break
            case let .failed(reason, inserted):
                return failedStreaming(reason: reason, source: text, output: inserted, language: locale.rawValue,
                    capture: CaptureResultFactory.polish(source: text, output: inserted))
            }
        }
        // Polish (the LLM tidy that adds punctuation) may be unavailable — no key,
        // offline, or the call fails. That must NOT kill the dictation: degrade to
        // the verbatim transcript so polished-by-default is safe with no LLM.
        var output = text
        var changes: [String] = []
        do {
            if let polished = try await polisher?.polish(text),
               !polished.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                output = polished.text
                changes = polished.changes
            }
        } catch {
            // keep verbatim `output` — punctuation is best-effort.
        }
        return .insert(
            capture: CaptureResultFactory.polish(source: text, output: output),
            item: item(source: text, language: locale.rawValue, output: output, reasons: changes))
    }

    public func rewrite(_ text: String, locale: CaptureLocale) async -> TextTransformOutcome {
        guard let rewriter else {
            return .failed(reason: "Rewrite service is not configured.", capture: nil, result: nil, item: nil)
        }
        let style = rewriteStyleProvider?() ?? .tone(rewriteToneProvider?() ?? .natural)
        // A StylePack carries its own prompt — it can't ride the streaming outlet.
        if case .tone = style, let streamingInsert {
            switch await streamingInsert(text, "rewrite", nil) {
            case let .streamed(inserted):
                return .streamed(
                    capture: CaptureResultFactory.rewriteSelection(source: text, output: inserted),
                    item: item(source: text, language: locale.rawValue, output: inserted, reasons: []))
            case .unsupportedFallback:
                break
            case let .failed(reason, inserted):
                return failedStreaming(reason: reason, source: text, output: inserted, language: locale.rawValue,
                    capture: CaptureResultFactory.rewriteSelection(source: text, output: inserted))
            }
        }
        do {
            let rewritten = try await rewriter.rewrite(text, style: style)
            let output = rewritten.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? text : rewritten.text
            return .insert(
                capture: CaptureResultFactory.rewriteSelection(source: text, output: output),
                item: item(source: text, language: locale.rawValue, output: output, reasons: rewritten.changes))
        } catch {
            return .failed(reason: error.localizedDescription, capture: nil, result: nil, item: nil)
        }
    }

    public func translate(_ text: String, preview: Bool, locale: CaptureLocale) async -> TextTransformOutcome {
        guard let translator else {
            return .failed(reason: "Translation service is not configured.", capture: nil, result: nil, item: nil)
        }
        let target = translationTargetProvider?() ?? .englishUS
        if !preview, let streamingInsert {
            switch await streamingInsert(text, "translate", target.rawValue) {
            case let .streamed(inserted):
                return .streamed(
                    capture: CaptureResultFactory.translateSelection(source: text, output: inserted),
                    item: item(source: text, language: locale.rawValue, output: inserted, reasons: []))
            case .unsupportedFallback:
                break
            case let .failed(reason, inserted):
                return failedStreaming(reason: reason, source: text, output: inserted, language: "translate:\(target.rawValue)",
                    capture: CaptureResultFactory.translateSelection(source: text, output: inserted))
            }
        }
        do {
            let translated = try await translator.translate(text, target: target)
            let output = translated.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? text : translated.text
            let capture = preview
                ? CaptureResultFactory.translatePreview(source: text, output: output)
                : CaptureResultFactory.translateSelection(source: text, output: output)
            return .insert(
                capture: capture,
                item: item(source: text, language: "translate:\(target.rawValue)", output: output, reasons: translated.notes))
        } catch {
            return .failed(reason: error.localizedDescription, capture: nil, result: nil, item: nil)
        }
    }

    public func express(_ text: String, using coach: CoachAPI, locale: CaptureLocale) async -> TextTransformOutcome {
        if let streamingInsert {
            switch await streamingInsert(text, "express", nil) {
            case let .streamed(inserted):
                let expr = ExpressionResult(idiomatic: inserted, original: text, reasons: [])
                return .streamedResult(
                    result: expr,
                    capture: CaptureResultFactory.coach(source: text, card: expr),
                    item: item(source: text, language: locale.rawValue, output: inserted, reasons: []))
            case .unsupportedFallback:
                break
            case let .failed(reason, inserted):
                if !inserted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let expr = ExpressionResult(idiomatic: inserted, original: text, reasons: [reason])
                    return .failed(
                        reason: reason,
                        capture: CaptureResultFactory.coach(source: text, card: expr),
                        result: expr,
                        item: item(source: text, language: locale.rawValue, output: inserted, reasons: [reason]))
                }
                return .failed(reason: reason, capture: nil, result: nil, item: nil)
            }
        }
        do {
            let expr = try await coach.express(text, context: contextProvider?())
            return .review(
                result: expr,
                capture: CaptureResultFactory.coach(source: text, card: expr),
                item: item(source: text, language: locale.rawValue, output: expr.idiomatic, reasons: expr.reasons))
        } catch {
            return .failed(reason: error.localizedDescription, capture: nil, result: nil, item: nil)
        }
    }

    // MARK: - Feedback modes (375 — prosody-coaching paths fold into the same descriptor)

    /// Analysis mode: keep the user's sentence, attach prosody coaching → review.
    public func analysisFeedback(_ text: String, using coach: CoachAPI, locale: CaptureLocale) async -> TextTransformOutcome {
        await prosodyReview(
            text, using: coach, locale: locale,
            heading: "分析模式: 先看语音、重音、语调和连读。",
            capture: { CaptureResultFactory.analysis(source: text, card: $0, prosody: $1) })
    }

    /// Practice mode: keep the user's sentence, give the next read-aloud target → review.
    public func practiceFeedback(_ text: String, using coach: CoachAPI, locale: CaptureLocale) async -> TextTransformOutcome {
        await prosodyReview(
            text, using: coach, locale: locale,
            heading: "练习模式: 保留你的句子,给出下一轮跟读目标。",
            capture: { CaptureResultFactory.practice(source: text, card: $0, prosody: $1) })
    }

    /// Shared analysis/practice shape: analyze → format reasons → `.review`; analyze
    /// failure errors out (mirrors the former per-method catch).
    private func prosodyReview(
        _ text: String, using coach: CoachAPI, locale: CaptureLocale,
        heading: String,
        capture: (ExpressionResult, ProsodyAnalysis) -> CaptureResult
    ) async -> TextTransformOutcome {
        do {
            let analysis = try await coach.analyze(text)
            let reasons = ProsodyReasonsFormatter().reasons(from: analysis, heading: heading)
            let card = ExpressionResult(idiomatic: text, original: text, reasons: reasons)
            return .review(
                result: card,
                capture: capture(card, analysis),
                item: item(source: text, language: locale.rawValue, output: text, reasons: reasons))
        } catch {
            return .failed(reason: error.localizedDescription, capture: nil, result: nil, item: nil)
        }
    }

    /// Teaching stage 1: express the intent in English (streaming or API). The VM
    /// inserts immediately and, for the API path, follows with `teachingAnalyze`.
    public func teachingExpress(_ text: String, using coach: CoachAPI, locale: CaptureLocale) async -> TeachingExpressStage {
        if let streamingInsert {
            switch await streamingInsert(text, "express", nil) {
            case let .streamed(inserted):
                let expr = ExpressionResult(idiomatic: inserted, original: text, reasons: [])
                return .streamed(capture: CaptureResultFactory.expressInEnglish(
                    source: text, insertText: inserted, coachCard: expr))
            case .unsupportedFallback:
                break
            case let .failed(reason, inserted):
                guard !inserted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return .streamedFailed(reason: reason, capture: nil, item: nil)
                }
                let expr = ExpressionResult(idiomatic: inserted, original: text, reasons: [reason])
                return .streamedFailed(
                    reason: reason,
                    capture: CaptureResultFactory.expressInEnglish(source: text, insertText: inserted, coachCard: expr),
                    item: item(source: text, language: locale.rawValue, output: inserted, reasons: [reason]))
            }
        }
        do {
            let expr = try await coach.express(text, context: contextProvider?())
            return .expressed(
                idiomatic: expr.idiomatic,
                exprReasons: expr.reasons,
                capture: CaptureResultFactory.expressInEnglish(
                    source: text, insertText: expr.idiomatic, coachCard: expr))
        } catch {
            return .failed(reason: error.localizedDescription)
        }
    }

    /// Teaching stage 2: prosody-enrich the already-inserted express text → review.
    /// Analyze failure degrades to a needs-network note (mirrors the former finishTeaching).
    public func teachingAnalyze(
        _ text: String, idiomatic: String, exprReasons: [String],
        using coach: CoachAPI, locale: CaptureLocale
    ) async -> TextTransformOutcome {
        let reasons: [String]
        let prosody: ProsodyAnalysis?
        do {
            let analysis = try await coach.analyze(idiomatic)
            reasons = exprReasons + ProsodyReasonsFormatter().reasons(
                from: analysis, heading: "教学模式: 这句应该这样说,再按下面的韵律朗读。")
            prosody = analysis
        } catch {
            reasons = exprReasons + ["联网后看韵律:韵律分析需要网络,已先给出表达改写。"]
            prosody = nil
        }
        let card = ExpressionResult(idiomatic: idiomatic, original: text, reasons: reasons)
        return .autoInsertedReview(
            result: card,
            capture: CaptureResultFactory.expressInEnglish(
                source: text, insertText: idiomatic, coachCard: card, prosody: prosody),
            item: item(source: text, language: locale.rawValue, output: idiomatic, reasons: reasons))
    }

    // MARK: - Helpers

    private func item(source: String, language: String, output: String, reasons: [String]) -> CaptureItem {
        CaptureItem(sourceText: source, language: language, idiomatic: output, reasons: reasons)
    }

    /// Mirror the former `recordFailedStreamingTransform`: persist + carry a capture
    /// only for a non-empty streamed partial, then enter error.
    private func failedStreaming(reason: String, source: String, output: String, language: String, capture: CaptureResult) -> TextTransformOutcome {
        let hasOutput = !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return .failed(
            reason: reason,
            capture: hasOutput ? capture : nil,
            result: nil,
            item: hasOutput ? item(source: source, language: language, output: output, reasons: [reason]) : nil)
    }
}
