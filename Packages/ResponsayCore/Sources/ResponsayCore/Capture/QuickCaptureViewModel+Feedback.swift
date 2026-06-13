import Foundation

// 375 (feedback slice) — the prosody-coaching DECISIONS (which CaptureResult, the
// streaming-vs-API express branch, prosody reason formatting) live in
// `CaptureTransformer`. analysis/practice fold into the `.review` outcome; teaching
// stays a two-phase flow (express → insert immediately → analyze → review) because
// the insert is staged *before* the slow prosody analyze, but each stage's decision
// is the transformer's. This extension just sets transcript, guards empty, applies.
extension QuickCaptureViewModel {
    func processAnalysisFeedback(_ text: String) async {
        transcript = text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { phase = .idle; return }
        await apply(await transformer.analysisFeedback(text, using: coach, locale: locale))
    }

    func processPracticeFeedback(_ text: String) async {
        transcript = text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { phase = .idle; return }
        await apply(await transformer.practiceFeedback(text, using: coach, locale: locale))
    }

    func processTeachingFeedback(_ text: String) async {
        transcript = text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { phase = .idle; return }
        switch await transformer.teachingExpress(text, using: coach, locale: locale) {
        case let .streamed(capture):
            captureResult = capture
            didAutoInsertResult = true
            phase = .idle
        case let .streamedFailed(reason, capture, item):
            if let capture {
                captureResult = capture
                didAutoInsertResult = true
            }
            if let item { try? store.save(item) }
            enterError(reason)
        case let .expressed(idiomatic, exprReasons, capture):
            // Insert the English now (low latency), then enrich with prosody.
            captureResult = capture
            do {
                try await CaptureResultInserter.insertIfNeeded(capture, using: inserter)
            } catch {
                enterError(error.localizedDescription)
                return
            }
            didAutoInsertResult = true
            await apply(await transformer.teachingAnalyze(
                text, idiomatic: idiomatic, exprReasons: exprReasons, using: coach, locale: locale))
        case let .failed(reason):
            enterError(reason)
        }
    }
}
