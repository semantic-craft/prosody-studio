import Foundation

// 372 — legal DECISIONS live in `LegalCaptureCoordinator` (routing, context
// assembly, scene classification, privacy gate, run building). This extension is
// now a thin orchestrator: call the coordinator, assign results to @Observable
// state, drive the phase machine. The insertion/verification-tag side effects
// (which touch `inserter`) intentionally stay here.
extension QuickCaptureViewModel {
    func processLegal(_ text: String) async {
        transcript = text
        guard let outcome = legal.route(text: text) else {
            enterError("法律技能未配置。")
            return
        }
        legalOutcome = outcome
        legalCandidates = outcome.cards
        phase = .review
    }

    public func evaluateScene(text: String) -> SceneStageClassification? {
        legal.evaluateScene(text: text)
    }

    public func selectLegalScene(_ scene: LegalScene) {
        guard let outcome = legalOutcome,
              let confirmed = legal.selectScene(scene, in: outcome) else { return }
        legalOutcome = confirmed
        legalCandidates = confirmed.cards
    }

    public func selectLegalCandidate(_ card: LegalCandidateCard) async {
        guard legal.isConfigured else { enterError("法律技能未配置。"); return }
        let decision = legal.privacyDecision(transcript: transcript)
        if decision.isBlocked {
            enterError(decision.reasons.first ?? "当前上下文已被隐私策略阻止发送。")
            return
        }
        if decision.requiresUserConfirm {
            pendingLegalCard = card
            legalSendConfirm = decision
            return
        }
        await runLegalSkill(card, route: decision.route)
    }

    public func confirmLegalSend() async {
        guard let card = pendingLegalCard else { return }
        legalSendConfirm = nil
        pendingLegalCard = nil
        await runLegalSkill(card, route: .cloudAllowed)
    }

    public func cancelLegalSend() {
        legalSendConfirm = nil
        pendingLegalCard = nil
    }

    func runLegalSkill(_ card: LegalCandidateCard, route: ModelRoute) async {
        guard legal.isConfigured else { enterError("法律技能未配置。"); return }
        let context = legal.executionContext(transcript: transcript)
        do {
            legalResponse = try await legal.execute(card: card, context: context, route: route)
            legalResponseRoute = route
            legal.recordRun(card: card, context: context, route: route, transcript: transcript)
        } catch {
            enterError("「\(card.title)」执行失败：\(error.localizedDescription)")
        }
    }

    public var legalSearchPermission: SearchPrivacyGate.SearchPermission {
        legal.searchPermission(route: legalResponseRoute)
    }

    public func verifyLegalAnchor(_ anchor: VerificationAnchor) async throws -> VerifiedSource? {
        try await legal.searchVerification(anchor, route: legalResponseRoute)
    }

    public func confirmLegalAnchor(_ anchor: VerificationAnchor, source: VerifiedSource) {
        guard let response = legalResponse else { return }
        var anchors = response.verificationAnchors
        guard let index = anchors.firstIndex(where: { $0.id == anchor.id }) else { return }
        SearchVerificationService.applyResult(source, to: &anchors[index])
        legalResponse = LegalSkillResponse(
            schemaVersion: response.schemaVersion,
            runId: response.runId,
            skillId: response.skillId,
            scene: response.scene,
            stage: response.stage,
            summary: response.summary,
            cards: response.cards,
            insertables: response.insertables,
            verificationAnchors: anchors,
            warnings: response.warnings)
    }

    public func insertLegalText(_ text: String, skipsTagging: Bool = false) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let tagged = skipsTagging ? text : VerificationPostProcessor().ensureTags(
            in: text, anchors: legalResponse?.verificationAnchors ?? [])
        do {
            try await inserter.insert(tagged)
        } catch {
            enterError(error.localizedDescription)
        }
    }
}
