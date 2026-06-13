import Foundation

// 375 — transform DECISIONS (streaming-vs-API, CaptureResult + persistence intent)
// live in `CaptureTransformer`. This extension is now thin: set transcript, guard
// empty, then `apply` the transformer's `TextTransformOutcome` to @Observable state.
extension QuickCaptureViewModel {
    /// The single place a transform result mutates the VM. Mirrors the former
    /// per-method captureResult / insert / save / phase blocks 1:1.
    func apply(_ outcome: TextTransformOutcome) async {
        switch outcome {
        case let .insert(capture, item):
            captureResult = capture
            phase = .idle
            do {
                try await CaptureResultInserter.insertIfNeeded(capture, using: inserter)
                try? store.save(item)
            } catch {
                enterError(error.localizedDescription)
            }
        case let .streamed(capture, item):
            captureResult = capture
            phase = .idle
            try? store.save(item)
        case let .review(result, capture, item):
            self.result = result
            selectedAlternative = nil
            captureResult = capture
            try? store.save(item)
            phase = .review
        case let .streamedResult(result, capture, item):
            self.result = result
            selectedAlternative = nil
            captureResult = capture
            try? store.save(item)
            phase = .idle
        case let .failed(reason, capture, result, item):
            if let result {
                self.result = result
                selectedAlternative = nil
            }
            if let capture { captureResult = capture }
            if let item { try? store.save(item) }
            enterError(reason)
        case let .autoInsertedReview(result, capture, item):
            self.result = result
            selectedAlternative = nil
            captureResult = capture
            try? store.save(item)
            didAutoInsertResult = true
            phase = .review
        }
    }

    func insertRawTranscript(_ text: String) async {
        transcript = text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { phase = .idle; return }
        await apply(transformer.raw(text, locale: locale))
    }

    func reviewTranscriptAfterPartialCleanupFailure(_ text: String) {
        transcript = text
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            enterError("实时预览文字未确认清除，且没有可恢复的最终文本。请检查目标输入框后重试。")
            return
        }
        let card = ExpressionResult(
            idiomatic: text,
            original: text,
            reasons: [
                "实时预览文字未确认清除，已暂停自动插入以避免重复上屏。请确认目标输入框后手动插入，或复制这段最终文本。"
            ])
        result = card
        selectedAlternative = nil
        captureResult = CaptureResultFactory.rawCopyOnly(text)
        phase = .review
    }

    func insertPolishedTranscript(_ text: String) async {
        transcript = text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { phase = .idle; return }
        await apply(await transformer.polish(text, locale: locale))
    }

    func rewriteAndInsert(_ text: String) async {
        transcript = text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { phase = .idle; return }
        await apply(await transformer.rewrite(text, locale: locale))
    }

    func translateAndInsert(_ text: String, preview: Bool = false) async {
        transcript = text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { phase = .idle; return }
        await apply(await transformer.translate(text, preview: preview, locale: locale))
    }

    func processTranscript(_ text: String, using activeCoach: CoachAPI) async {
        transcript = text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { phase = .idle; return }
        await apply(await transformer.express(text, using: activeCoach, locale: locale))
    }
}
