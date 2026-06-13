import Foundation

// MARK: - 220 EnabledLegalSkillStore
//
// Which legal skills are enabled in the ⌥L palette. Replaces the old decorative
// `@State legalSkills: Set<String>` (Chinese display strings, no consumer) with a
// real, persisted set of skill **ids** that `LegalSkillRuntime` filters candidates
// against, the Settings toggles write to, and onboarding seeds.
//
// `nil` (never set) → the 5 default-enabled built-ins. `[]` (user turned everything
// off) → empty, deliberately distinct from the default. Imported skills (122+) start
// **disabled**, so they only appear after the user explicitly enables them.

public struct EnabledLegalSkillStore {
    public static let defaultsKey = "legal.enabledSkills"
    public static let temporarilyHiddenIDs: Set<String> = [
        "litigation.labor_fee_calculator.cn",
    ]

    /// The 5 default-enabled built-in skill ids (one per first-class legal action).
    /// Onboarding (法律用途) seeds these defaults (e.g. `practice.case_strategy.cn`) from here.
    public static let defaultEnabledIDs: Set<String> = [
        "practice.case_strategy.cn",             // 案件策略评估
        "practice.evidence_review.cn",           // 证据审查与质证
        "practice.claim_and_defense.cn",         // 请求权与抗辩分析
        "research.search_strategy.cn",           // 检索策略生成
        "verification.fact_check.cn",            // 事实核查与穿透
    ]

    /// Pure resolve so the default/empty distinction is unit-testable without UserDefaults.
    /// `nil` (key absent) → defaults; any array (incl. empty) → exactly that set.
    public static func resolve(stored: [String]?) -> Set<String> {
        let ids = stored.map(Set.init) ?? defaultEnabledIDs
        return ids.subtracting(temporarilyHiddenIDs)
    }

    public static func isTemporarilyHidden(_ id: String) -> Bool {
        temporarilyHiddenIDs.contains(id)
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var enabledIDs: Set<String> {
        Self.resolve(stored: defaults.array(forKey: Self.defaultsKey) as? [String])
    }

    public func isEnabled(_ id: String) -> Bool { enabledIDs.contains(id) }

    /// Toggle one skill on/off and persist. Writes a sorted array so storage is stable.
    public func setEnabled(_ enabled: Bool, id: String) {
        guard !Self.isTemporarilyHidden(id) else { return }
        var ids = enabledIDs
        if enabled { ids.insert(id) } else { ids.remove(id) }
        defaults.set(ids.sorted(), forKey: Self.defaultsKey)
    }

    /// Force a skill on (onboarding's mandated 立案评估), preserving the rest.
    public func ensureEnabled(_ id: String) { setEnabled(true, id: id) }
}
