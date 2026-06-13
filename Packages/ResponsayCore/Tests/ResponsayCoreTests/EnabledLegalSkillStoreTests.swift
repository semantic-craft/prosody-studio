import Testing
import Foundation
@testable import ResponsayCore

/// 220 — EnabledLegalSkillStore: which legal skills are enabled in the ⌥L palette.
/// Pure resolve (default vs explicit) + a UserDefaults-backed instance the Settings
/// toggles + onboarding write to. nil (never set) → 5 built-in defaults; [] (user
/// turned everything off) → empty, distinct from default.
struct EnabledLegalSkillStoreTests {

    // MARK: pure resolve

    @Test func resolve_whenUnset_returnsFiveDefaultBuiltins() {
        let ids = EnabledLegalSkillStore.resolve(stored: nil)
        #expect(ids == EnabledLegalSkillStore.defaultEnabledIDs)
        #expect(ids.count == 5)
    }

    @Test func resolve_emptyStored_meansAllDisabled_notDefault() {
        #expect(EnabledLegalSkillStore.resolve(stored: []) == [])
    }

    @Test func resolve_storedIDs_roundTrip() {
        #expect(EnabledLegalSkillStore.resolve(stored: ["a.cn", "b.cn"]) == ["a.cn", "b.cn"])
    }

    @Test func resolve_storedHiddenIDs_areFiltered() {
        let ids = EnabledLegalSkillStore.resolve(stored: [
            "litigation.private_lending_interest.cn",
            "litigation.labor_fee_calculator.cn",
        ])
        #expect(ids == ["litigation.private_lending_interest.cn"])
    }

    // MARK: UserDefaults-backed

    private func freshStore(_ name: String) -> (EnabledLegalSkillStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (EnabledLegalSkillStore(defaults: defaults), defaults)
    }

    @Test func store_defaultsWhenUnset() {
        let (store, _) = freshStore("test.enabled.default")
        #expect(store.enabledIDs == EnabledLegalSkillStore.defaultEnabledIDs)
    }

    @Test func store_setEnabledFalse_persistsAcrossInstances() {
        let (store, defaults) = freshStore("test.enabled.persist")
        let target = "verification.fact_check.cn"
        store.setEnabled(false, id: target)
        let reopened = EnabledLegalSkillStore(defaults: defaults)
        #expect(!reopened.isEnabled(target))
        #expect(reopened.isEnabled("practice.case_strategy.cn"))
    }

    @Test func store_ensureEnabled_addsForcedOnboardingSkill() {
        let (store, _) = freshStore("test.enabled.ensure")
        let forced = "practice.case_strategy.cn"
        store.setEnabled(false, id: forced)
        store.ensureEnabled(forced)
        #expect(store.isEnabled(forced))
    }

    @Test func store_setEnabledHiddenSkill_isIgnored() {
        let (store, _) = freshStore("test.enabled.hidden")
        store.setEnabled(true, id: "litigation.labor_fee_calculator.cn")
        #expect(!store.isEnabled("litigation.labor_fee_calculator.cn"))
    }
}
