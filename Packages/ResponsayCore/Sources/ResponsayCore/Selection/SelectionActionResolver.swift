import Foundation

/// Decides the **gated action set** for a text selection (issue 127 / ADR-0022).
/// Rules-first, no model: legal context surfaces the skill palette; an English
/// sentence surfaces the oral-practice entries; everything offers the two
/// transforms + bounded ask. Empty selection → nothing (downgrade, ADR-0008).
public struct SelectionActionResolver: Sendable {
    public init() {}

    public func actions(
        classification: SelectionClassification,
        scene: SceneStageClassification? = nil,
        hasSelection: Bool = true,
        hasVerifiableFacts: Bool = false
    ) -> [SelectionAction] {
        guard hasSelection else { return [] }

        var actions: [SelectionAction] = []

        // Legal context (scene confidently not unknown) → palette first.
        if let scene, scene.scene != .unknown {
            actions.append(.legalSkill)
        }

        // The selection carries extractable fact coordinates (法条/案号/文献…)
        // → one-tap source verification (215). Driven by the selected *text*
        // itself, not the AX scene — so it still appears in browsers/Electron
        // hosts where the scene pipeline cannot see the selection.
        if hasVerifiableFacts {
            actions.append(.verify)
        }

        // The two transforms are always available.
        actions.append(.polish)
        actions.append(.translate)

        // English, sentence-shaped → idiomatic coach first (the core product
        // story's selection entry — dead leaf until 300), then oral practice.
        if classification.isEnglishPracticeEligible {
            actions.append(.coachIdiomatic)
            actions.append(.analyzeProsody)
            actions.append(.enterRepeat)
            actions.append(.readAloud)
        }

        // Term-shaped fragment (1–2 words / 短专名, not a clause, carries
        // letters) → offer the recognition dictionary (300). Sentences are
        // excluded: the dictionary biases hotwords, not prose.
        if !classification.isSentenceShaped, classification.script != .other {
            actions.append(.addToDictionary)
        }

        // Bounded structured help — last, never an open chat.
        actions.append(.ask)
        return actions
    }
}
