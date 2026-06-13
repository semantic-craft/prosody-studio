import Testing
import Foundation
@testable import ResponsayCore

/// 112 — capstone integration: the full legal chain composes (sans live model).
/// context → ContextSignalLayer (113–117) → router (104) → palette (105) →
/// execute (106) → validate/repair/fallback → backfill (108) → renderer (107).
struct LegalBrainEndToEndTests {
    private let now = Date(timeIntervalSince1970: 0)

    /// A structured model reply whose summary cites a 法条 the model did NOT anchor.
    private func modelReplyCitingUnanchoredLaw() -> String {
        let r = LegalSkillResponse(
            runId: "model", skillId: "model", scene: .litigation, stage: .briefDrafting,
            summary: "依据《个保法》第24条，处理者应承担相应责任。",
            cards: [.cnkiQuery(CNKIQueryCard(title: "检索式", expertQuery: "SU=('违约') AND SU=('证据')"))],
            verificationAnchors: [])
        return String(data: try! JSONEncoder().encode(r), encoding: .utf8)!
    }

    @Test func anchorA_routesExecutesBackfillsAndRenders() async throws {
        let mock = MockLegalExecutor(outputs: [modelReplyCitingUnanchoredLaw()])
        let runtime = try LegalSkillRuntime.bundled(executor: mock)
        let ctx = ExpressionContext(
            appName: "Microsoft Word", bundleIdentifier: "com.microsoft.word",
            windowTitle: "起诉状.docx", selectedText: "被告拖欠货款，构成违约。",
            textBeforeCursor: "一、事实与理由\n……")

        // 104/105: classify + palette
        let outcome = runtime.route(context: ctx, now: now)
        #expect(outcome.scene == .litigation)
        let card = try #require(outcome.cards.first { $0.skillId == "practice.claim_and_defense.cn" })

        // 106 + 108: execute → validate → backfill the missing [待核] anchor
        let response = try await runtime.execute(card: card, context: ctx)
        #expect(response.summary.contains("《个保法》第24条"))
        #expect(response.verificationAnchors.contains { $0.label == "《个保法》第24条" && $0.status == .pending })

        // 107: renderer surfaces the query insert affordance
        let affordances = LegalCardRenderer().affordances(for: response)
        #expect(affordances.contains { $0.kind == .query })
    }

    @Test func privacyBlock_neverFallsBackToCloud() {
        // 110: a secure field blocks the legal path; nothing is sent, route is not cloud.
        let decision = LegalPrivacyPolicy().decide(gate: .denied(.secureTextField), selectedText: "客户保密")
        #expect(decision.route == .blocked)
        #expect(decision.allowsCloud == false)
        #expect(decision.sendFields.isEmpty)
    }

    @Test func registryLoadFailureIsolation_doesNotAffectLegacy() throws {
        // Failure isolation: an empty registry (stand-in for a load failure) still yields a
        // usable runtime — the router downgrades to generic actions, never crashes.
        let runtime = LegalSkillRuntime(registry: try LegalSkillRegistry([]))
        let ctx = ExpressionContext(
            appName: "Microsoft Word", bundleIdentifier: "com.microsoft.word",
            windowTitle: "起诉状.docx", selectedText: "被告拖欠货款。",
            textBeforeCursor: "一、事实与理由\n……")
        let outcome = runtime.route(context: ctx, now: now)
        #expect(outcome.cards.isEmpty == false)             // generic fallback actions
        #expect(outcome.cards.allSatisfy { $0.skillId.hasPrefix("generic.") })
    }
}
