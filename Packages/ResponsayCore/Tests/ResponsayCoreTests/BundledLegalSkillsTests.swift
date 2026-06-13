import Testing
import Foundation
@testable import ResponsayCore

/// 103 — the bundled v0 legal-skill corpus (10 skills: 2 anchors + 8 stubs)
/// authored under `LegalBrain/LegalSkills/`, compiled via 102, loaded through the
/// SwiftPM resource bundle. Asserts compilation + indexing + anchor completeness.
/// (Schema validity ≠ legal correctness — the builder's correctness sign-off is
/// tracked in the issue's `## Comments`.)
struct BundledLegalSkillsTests {

    private func registry() throws -> LegalSkillRegistry {
        try LegalSkillRegistry.loadBundled()
    }

    @Test func bundleDirectoryResolves() throws {
        #expect(LegalSkillRegistry.bundledSkillsDirectory() != nil)
    }

    @Test func allSkillsCompile() throws {
        #expect(try registry().skills.count == 16)
    }

    @Test func indexesIntoThreeScenes() throws {
        let reg = try registry()
        let scenes = Set(reg.skills.map(\.metadata.sceneLayer.scene))
        #expect(scenes == [.litigation, .academicWriting, .unknown])
        #expect(reg.candidates(scene: .litigation).count == 7)
        #expect(reg.candidates(scene: .academicWriting).count == 6)
        // 325 slice 3b: the 3 unknown-scene entries are the bundled style.* skills
        // (kind:rewrite) — they belong to the 改写风格 picker, not the ⌥L
        // generation palette, so they no longer surface as generation candidates.
        #expect(reg.candidates(scene: .unknown).count == 0)
    }

    @Test func candidatesNeverIncludeRewriteKindSkills() throws {
        let reg = try registry()
        for scene in [LegalScene.litigation, .academicWriting, .unknown] {
            #expect(reg.candidates(scene: scene).allSatisfy { $0.metadata.kind != .rewrite })
        }
        // The style.* skills still exist in the raw index (for the rewrite picker),
        // they're just not generation candidates.
        #expect(reg.skills.contains { $0.metadata.kind == .rewrite })
    }

    @Test func everyDomainMatchesSceneLayer() throws {
        // No skill should declare a domain that disagrees with its sceneLayer scene.
        for skill in try registry().skills {
            #expect(skill.metadata.domain == skill.metadata.sceneLayer.scene)
        }
    }

    @Test func anchorsAreFullyStructured() throws {
        let reg = try registry()

        let a = try #require(reg.skill(id: "practice.evidence_review.cn"))
        #expect(a.metadata.outputCards.contains(.legalAnalysis))
        #expect(a.metadata.risk.level == .medium)
        #expect(a.reasoningProcedure.contains("质证"))
        #expect(a.outputConstraint.contains("LEGAL_OUTPUT/v1"))

        let b = try #require(reg.skill(id: "practice.claim_and_defense.cn"))
        #expect(b.metadata.outputCards.contains(.legalAnalysis))
        #expect(b.metadata.outputCards.contains(.strategyRecommendation))
        #expect(b.outputConstraint.contains("LEGAL_OUTPUT/v1"))
    }

    @Test func nonStyleSkillsCarryDisclaimerAndMandatoryMapping() throws {
        for skill in try registry().skills {
            let isStyle = skill.metadata.id.hasPrefix("style.")
            if !isStyle {
                #expect(!skill.metadata.reasoningKernel.mandatoryMapping.isEmpty)
                #expect(!skill.metadata.risk.disclaimer.isEmpty)
            }
            let hasContent = !skill.skillInstructions.isEmpty
                || !skill.reasoningProcedure.isEmpty
                || !skill.outputConstraint.isEmpty
                || !(skill.metadata.prompt?.isEmpty ?? true)
                || !skill.metadata.reasoningKernel.mandatoryMapping.isEmpty
            #expect(hasContent, "skill \(skill.metadata.id) has no instructions/procedure/prompt")
        }
    }

    @Test func routerSurfacesBundledLitigationAnchor() throws {
        // End-to-end: a litigation brief context routes to the bundled anchor A.
        let ctx = ExpressionContext(
            appName: "Microsoft Word",
            bundleIdentifier: "com.microsoft.word",
            windowTitle: "起诉状.docx",
            selectedText: "被告拖欠货款,构成违约。",
            textBeforeCursor: "一、事实与理由\n……"
        )
        let bundle = ContextSignalLayer().assemble(context: ctx, now: Date(timeIntervalSince1970: 0))
        let decision = LegalSceneStageRouter().route(bundle, registry: try registry())
        #expect(decision.tier == "auto")
        #expect(decision.cards.contains { $0.skillId == "practice.claim_and_defense.cn" })
    }
}
