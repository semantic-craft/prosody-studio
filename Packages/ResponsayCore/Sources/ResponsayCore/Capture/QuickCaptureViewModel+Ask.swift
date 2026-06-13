import Foundation

extension QuickCaptureViewModel {
    public func prepareAskAndListen(context: String) async {
        guard phase != .listening, phase != .thinking else { return }
        let mode: SelectionAskMode =
            (evaluateScene(text: context)?.scene ?? .unknown) != .unknown ? .legal : .general
        startListening(outputMode: .askSelection)
        guard phase == .listening else { return }
        askSession = SelectionAskSession(rawSelection: context, mode: mode)
    }

    func processAskSelection(_ question: String) async {
        transcript = question
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            phase = .idle
            return
        }
        var session = askSession ?? SelectionAskSession(rawSelection: "")
        session = session.asking(question)
        do {
            let expr = try await coach.ask(question, context: session.selection)
            let disciplined = Self.applyAskDiscipline(expr, session: session)
            askSession = session.answeringLast(disciplined.idiomatic)
            result = disciplined
            selectedAlternative = nil
            captureResult = CaptureResultFactory.coach(source: question, card: disciplined)
            try? store.save(CaptureItem(
                sourceText: question, language: locale.rawValue,
                idiomatic: activeIdiomatic, reasons: disciplined.reasons))
            phase = .review
        } catch {
            enterError(error.localizedDescription)
        }
    }

    nonisolated static func applyAskDiscipline(
        _ expr: ExpressionResult, session: SelectionAskSession
    ) -> ExpressionResult {
        guard session.mode == .legal else { return expr }
        let processor = VerificationPostProcessor()
        func disciplined(_ text: String) -> String {
            processor.ensureTags(in: text, anchors: session.guardedLegalAnchors(for: text))
        }
        return ExpressionResult(
            idiomatic: disciplined(expr.idiomatic),
            original: expr.original,
            reasons: expr.reasons,
            thinkingShift: expr.thinkingShift,
            alternatives: expr.alternatives.map(disciplined))
    }
}
