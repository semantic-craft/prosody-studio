import Foundation

// MARK: - 人身损害赔偿：整案组装（compute）
//
// 按法定明细顺序拼装各赔偿项（实报项 → 住院伙食 → 营养 → 误工 → 护理 → 残疾/死亡赔偿金 →
// 丧葬费(仅死亡) → 被扶养人 → 精神抚慰金）→ 明细 + 合计。
// 残疾/死亡赔偿金基数(disabilityDeathBase)与被扶养人消费基数(dependentConsumptionBase)
// 须由调用方按城乡口径解析后传入；前者缺省时回退全国可支配收入表。

public enum PersonalInjuryCaseType: String, Codable, Sendable {
    case injury  // 伤残
    case death   // 死亡
}

public struct PersonalInjuryLine: Sendable, Equatable {
    public let item: String
    public let amount: Decimal
    public init(item: String, amount: Decimal) { self.item = item; self.amount = amount }
}

public struct PersonalInjuryResult: Sendable, Equatable {
    public let lines: [PersonalInjuryLine]
    public let total: Decimal
}

public struct PersonalInjuryCase: Sendable {
    public var caseType: PersonalInjuryCaseType
    public var victimAge: Int
    public var province: String
    public var baseYear: Int                       // 一审法庭辩论终结时的上一统计年度
    public var wageCaliber: WageCaliber = .privateUnit
    public var disabilityLevels: [Int] = []
    public var dependents: [Dependent] = []
    public var disabilityDeathBase: Decimal? = nil // 残疾/死亡赔偿金基数（城镇可支配/农村纯收入）
    public var dependentConsumptionBase: Decimal? = nil

    // 误工
    public var workLossDays: Int = 0
    public var lostIncomeActual: Decimal? = nil
    public var annualIncomeAverage: Decimal? = nil
    public var industryAverage: Decimal? = nil
    // 护理
    public var nursingDays: Int = 0
    public var nursingRatePerDay: Decimal? = nil
    public var nursingAnnualIncome: Decimal? = nil
    // 营养 / 住院伙食
    public var nutritionDays: Int = 0
    public var nutritionRatePerDay: Decimal = 50
    public var hospitalDays: Int = 0
    public var hospitalFoodRatePerDay: Decimal = 100
    // 实报项
    public var medicalExpense: Decimal = 0
    public var transportExpense: Decimal = 0
    public var lodgingExpense: Decimal = 0
    public var appraisalFee: Decimal = 0
    public var propertyLoss: Decimal = 0
    public var assistiveDeviceExpense: Decimal = 0
    // 精神
    public var mentalDamage: Decimal? = nil

    public init(caseType: PersonalInjuryCaseType, victimAge: Int, province: String, baseYear: Int) {
        self.caseType = caseType
        self.victimAge = victimAge
        self.province = province
        self.baseYear = baseYear
    }
}

extension PersonalInjuryCalculator {

    public func compute(_ c: PersonalInjuryCase) throws -> PersonalInjuryResult {
        var lines: [PersonalInjuryLine] = []
        func add(_ item: String, _ amount: Decimal) {
            if amount > 0 { lines.append(PersonalInjuryLine(item: item, amount: Self.round2(amount))) }
        }

        // 1 实报项（固定顺序）
        add("医疗费", c.medicalExpense)
        add("交通费", c.transportExpense)
        add("住宿费", c.lodgingExpense)
        add("鉴定费", c.appraisalFee)
        add("财产损失", c.propertyLoss)
        add("残疾辅助器具费", c.assistiveDeviceExpense)
        // 2 住院伙食 / 3 营养
        add("住院伙食补助费", hospitalMealFee(ratePerDay: c.hospitalFoodRatePerDay, days: c.hospitalDays))
        add("营养费", nutritionFee(ratePerDay: c.nutritionRatePerDay, days: c.nutritionDays))
        // 4 误工 / 5 护理
        if c.workLossDays > 0 {
            add("误工费", try lostIncomeFee(actualTotal: c.lostIncomeActual,
                                            annualIncome: c.annualIncomeAverage,
                                            industryAnnual: c.industryAverage, days: c.workLossDays))
        }
        if c.nursingDays > 0 {
            add("护理费", try nursingFee(ratePerDay: c.nursingRatePerDay,
                                        annualIncome: c.nursingAnnualIncome, days: c.nursingDays))
        }
        // 6 残疾/死亡赔偿金 + 7 丧葬费
        switch c.caseType {
        case .injury:
            if !c.disabilityLevels.isEmpty {
                add("残疾赔偿金", try disabilityCompensation(disposableIncome: try resolveBase(c),
                                                            age: c.victimAge, levels: c.disabilityLevels))
            }
        case .death:
            add("死亡赔偿金", deathCompensation(disposableIncome: try resolveBase(c), age: c.victimAge))
            add("丧葬费", try funeralFee(province: c.province, baseYear: c.baseYear, caliber: c.wageCaliber))
        }
        // 8 被扶养人生活费
        if !c.dependents.isEmpty {
            guard let consumption = c.dependentConsumptionBase else {
                throw PersonalInjuryError.missingConsumptionBase
            }
            let amounts = try dependentSupportFee(consumptionBase: consumption, dependents: c.dependents)
            for (i, dep) in c.dependents.enumerated() {
                let label = dep.label.isEmpty ? "\(dep.age)岁被扶养人" : dep.label
                add("被扶养人生活费（\(label)）", amounts[i])
            }
        }
        // 9 精神损害抚慰金
        if let m = c.mentalDamage { add("精神损害抚慰金", m) }

        let total = lines.reduce(Decimal(0)) { $0 + $1.amount }
        return PersonalInjuryResult(lines: lines, total: Self.round2(total))
    }

    /// 残疾/死亡赔偿金基数：显式传入优先，否则回退全国城镇可支配收入表（按 baseYear）。
    private func resolveBase(_ c: PersonalInjuryCase) throws -> Decimal {
        if let b = c.disabilityDeathBase { return b }
        if let national = nationalDisposable(baseYear: c.baseYear) { return national }
        throw PersonalInjuryError.missingDisposableBase
    }
}
