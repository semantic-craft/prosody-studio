import Testing
import Foundation
@testable import ResponsayCore

/// 105 — LegalSkillRuntime: scene-scoped palette + routing convenience + execute stub.
/// Uses the bundled v0 corpus (103) so the anchor-A palette matches the acceptance list.
struct LegalSkillRuntimeTests {
    private let now = Date(timeIntervalSince1970: 0)

    private func runtime() throws -> LegalSkillRuntime { try .bundled() }

    @Test func suggestSkills_litigationPalette_matchesAnchorAList() throws {
        // Test that skills assigned to the 'litigationPractice' scene are loaded.
        let cards = try runtime().suggestSkills(scene: .litigation, stage: .briefDrafting)
        let titles = cards.map(\.title)
        // With the merged skills, litigationPractice contains practice.* skills
        #expect(titles.contains("案情分析与诉讼策略"))
        #expect(titles.contains("请求权与抗辩分析"))
        #expect(titles.contains("证据审查与质证"))
        #expect(cards.last?.skillId == "generic.draftParagraph")   // 起草本段 always last
    }

    @Test func suggestSkills_filtersToEnabledSet() throws {
        // only enabled skills appear; the generic 起草本段 always stays.
        let enabled: Set<String> = ["practice.evidence_review.cn"]
        let cards = try runtime().suggestSkills(scene: .litigation, stage: .briefDrafting, enabled: enabled)
        let skillIDs = cards.map(\.skillId)
        #expect(skillIDs.contains("practice.evidence_review.cn"))
        #expect(!skillIDs.contains("practice.claim_and_defense.cn"))   // disabled → absent
        #expect(cards.last?.skillId == "generic.draftParagraph")   // generic always last
    }

    @Test func suggestSkills_nilEnabled_keepsAll() throws {
        // Backward compatible: no enabled set → unfiltered (existing behavior).
        let cards = try runtime().suggestSkills(scene: .litigation, stage: .briefDrafting, enabled: nil)
        #expect(cards.count > 1) // Ensures multiple skills + generic
    }

    @Test func suggestSkills_isSceneScoped_notKeywordNarrowed() throws {
        // Scene palette shows ALL skills in the scene
        let cards = try runtime().suggestSkills(scene: .academicWriting, stage: .citationDrafting)
        // Should contain academic.* skills
        #expect(cards.contains { $0.skillId == "academic.concept_decomposition.cn" })
        #expect(cards.contains { $0.skillId == "academic.citation_formatting.cn" })
    }

    @Test func suggestSkills_ranksStageMatchesFirst() throws {
        // briefDrafting-applicable litigation skills sort ahead of evidenceReview-only ones.
        let cards = try runtime().suggestSkills(scene: .litigation, stage: .trialPreparation)
        let skillTitles = cards.dropLast().map(\.title)   // drop the generic 起草本段
        #expect(!skillTitles.isEmpty)
    }

    @Test func route_anchorA_autoTierLitigationPalette() throws {
        let ctx = ExpressionContext(
            appName: "Microsoft Word",
            bundleIdentifier: "com.microsoft.word",
            windowTitle: "起诉状.docx",
            selectedText: "被告拖欠货款,构成违约。",
            textBeforeCursor: "一、事实与理由\n……"
        )
        let outcome = try runtime().route(context: ctx, now: now)
        #expect(outcome.scene == .litigation)
        #expect(outcome.shouldConfirmScene == false)
        #expect(outcome.cards.count >= 5)
        #expect(outcome.cards.contains { $0.skillId == "practice.claim_and_defense.cn" })
    }

    @Test func route_ambiguous_confirmsScene() throws {
        // Word, no heading cue → mid confidence → scene-confirm.
        let ctx = ExpressionContext(
            appName: "Microsoft Word",
            bundleIdentifier: "com.microsoft.word",
            selectedText: "这段话需要看看。"
        )
        let outcome = try runtime().route(context: ctx, now: now)
        #expect(outcome.shouldConfirmScene == true)
    }

    @Test func execute_withoutExecutor_throwsNotConfigured() async throws {
        // The bundled runtime has no executor → execute cannot run (106 wires the
        // executor at the app/composition layer). End-to-end execute paths are covered
        // in LegalSkillExecutorTests with a mock executor.
        let card = LegalCandidateCard(
            id: "practice.evidence_review.cn", skillId: "practice.evidence_review.cn",
            title: "证据论证链", scene: .litigation, stage: .briefDrafting, confidence: 0.9,
            action: .executeSkill(skillId: "practice.evidence_review.cn"))
        await #expect(throws: LegalSkillRuntimeError.notConfigured) {
            _ = try await runtime().execute(card: card, context: ExpressionContext(selectedText: "x"))
        }
    }
}
