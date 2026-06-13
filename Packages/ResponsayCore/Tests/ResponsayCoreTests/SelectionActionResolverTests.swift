import Testing
import Foundation
@testable import ResponsayCore

/// 127 — selection action menu routing. Verification: the four paths; no
/// free-form chat; only the main transform auto-inserts.
struct SelectionActionResolverTests {
    private let resolver = SelectionActionResolver()
    private let classifier = SelectionClassifier()

    private func scene(_ s: LegalScene) -> SceneStageClassification {
        SceneStageClassification(scene: s, stage: .briefDrafting, confidence: 0.8, reasons: [], shouldAskUser: false)
    }

    @Test func englishSentence_offersRepeatEntry() {
        let c = classifier.classify("I want to know if you can finish this by tomorrow.")
        let actions = resolver.actions(classification: c)
        #expect(actions.contains(.enterRepeat))      // 进跟读
        #expect(actions.contains(.readAloud))
        #expect(actions.contains(.polish))
        #expect(actions.contains(.translate))
        #expect(actions.contains(.legalSkill) == false)
    }

    // 300: the core story's selection entry —「地道表达」leads the English
    // practice group; a sentence is NOT offered the dictionary chip.
    @Test func englishSentence_coachIdiomaticLeadsPracticeGroup() throws {
        let c = classifier.classify("I want to know if you can finish this by tomorrow.")
        let actions = resolver.actions(classification: c)
        let coachIndex = try #require(actions.firstIndex(of: .coachIdiomatic))
        let prosodyIndex = try #require(actions.firstIndex(of: .analyzeProsody))
        #expect(coachIndex < prosodyIndex)
        #expect(actions.contains(.addToDictionary) == false)   // sentence ≠ term
    }

    // 300: a term-shaped fragment (专名/术语) offers「加入词典」; digits/symbols
    // alone (no letters) do not.
    @Test func termFragment_offersDictionaryChip() {
        let term = classifier.classify("Responsay")
        #expect(resolver.actions(classification: term).contains(.addToDictionary))

        let hanTerm = classifier.classify("北大法宝")
        #expect(resolver.actions(classification: hanTerm).contains(.addToDictionary))

        let digits = classifier.classify("12345")
        #expect(resolver.actions(classification: digits).contains(.addToDictionary) == false)
    }

    @Test func legalContext_offersSkillPalette() {
        let c = classifier.classify("被告应承担违约责任")   // Chinese → not practice-eligible
        let actions = resolver.actions(classification: c, scene: scene(.litigation))
        #expect(actions.first == .legalSkill)        // palette surfaces first for legal
        #expect(actions.contains(.enterRepeat) == false)
    }

    @Test func chineseFragment_minimalSet() {
        let c = classifier.classify("你好")
        let actions = resolver.actions(classification: c, scene: scene(.unknown))
        // No legal, no English practice; the fragment IS offered the dictionary (300).
        #expect(actions == [.polish, .translate, .addToDictionary, .ask])
    }

    @Test func emptySelection_noActions() {
        let c = classifier.classify("")
        #expect(resolver.actions(classification: c, hasSelection: false).isEmpty)
    }

    @Test func legalEnglishSentence_offersBoth() {
        let c = classifier.classify("The defendant shall bear liability for the breach of contract.")
        let actions = resolver.actions(classification: c, scene: scene(.litigation))
        #expect(actions.contains(.legalSkill))
        #expect(actions.contains(.enterRepeat))
    }

    @Test func noFreeFormChat_askIsBounded() {
        // There is no generic "chat" action; the only ask-like action is bounded.
        #expect(SelectionAction.allCases.contains { $0.rawValue.lowercased().contains("chat") } == false)
        #expect(SelectionAction.ask.isBounded)
    }

    @Test func onlyMainTransformAutoInserts() {
        #expect(SelectionAction.polish.autoInserts)
        #expect(SelectionAction.translate.autoInserts)
        for action in [SelectionAction.legalSkill, .verify, .enterRepeat, .readAloud, .ask,
                       .coachIdiomatic, .addToDictionary] {
            #expect(action.autoInserts == false)
        }
    }

    // MARK: - verify chip (215 shortest path, audit area 3)

    @Test func verifiableFacts_surfaceVerifyChip_evenWithoutScene() {
        // Text-driven: a 法条 citation in a browser (scene unknown/nil) must
        // still offer one-tap verification.
        let c = classifier.classify("《民法典》第五百条规定了缔约过失责任。")
        let actions = resolver.actions(classification: c, scene: nil, hasVerifiableFacts: true)
        #expect(actions.contains(.verify))
        #expect(actions.contains(.legalSkill) == false)  // no scene → no palette
    }

    @Test func noVerifiableFacts_noVerifyChip() {
        let c = classifier.classify("请帮我看看这段话通不通顺。")
        let actions = resolver.actions(classification: c)
        #expect(actions.contains(.verify) == false)
    }

    @Test func verifyChipOrderedAfterLegalSkill() {
        let c = classifier.classify("依据《民法典》第五百条……")
        let actions = resolver.actions(
            classification: c, scene: scene(.litigation), hasVerifiableFacts: true)
        let legalIdx = actions.firstIndex(of: .legalSkill)
        let verifyIdx = actions.firstIndex(of: .verify)
        #expect(legalIdx != nil && verifyIdx != nil && legalIdx! < verifyIdx!)
    }
}
