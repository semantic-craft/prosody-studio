import Foundation

// MARK: - 人身损害赔偿：其余赔偿项（误工/护理/营养/住院伙食/被扶养人生活费）

public struct Dependent: Sendable, Equatable {
    public let age: Int
    public let supporterCount: Int      // 扶养义务人数（含本案被告外的其他义务人）
    public let noLaborCapacity: Bool    // 成年被扶养人须无劳动能力
    public let label: String
    public init(age: Int, supporterCount: Int = 1, noLaborCapacity: Bool = false, label: String = "") {
        self.age = age
        self.supporterCount = supporterCount
        self.noLaborCapacity = noLaborCapacity
        self.label = label
    }
}

extension PersonalInjuryCalculator {

    /// 营养费 = 单价 × 天数（默认 50 元/天）。天数 ≤0 → 0。
    public func nutritionFee(ratePerDay: Decimal = 50, days: Int) -> Decimal {
        days > 0 ? Self.round2(ratePerDay * Decimal(days)) : 0
    }

    /// 住院伙食补助费 = 单价 × 天数（默认 100 元/天）。天数 ≤0 → 0。
    public func hospitalMealFee(ratePerDay: Decimal = 100, days: Int) -> Decimal {
        days > 0 ? Self.round2(ratePerDay * Decimal(days)) : 0
    }

    /// 误工费（按优先级）：实际减少总收入直取 → 最近三年平均年收入÷365×天 → 同行业年薪÷365×天。
    /// 天数 ≤0 → 0；三者皆无 → 报错。
    public func lostIncomeFee(actualTotal: Decimal? = nil, annualIncome: Decimal? = nil,
                              industryAnnual: Decimal? = nil, days: Int) throws -> Decimal {
        guard days > 0 else { return 0 }
        if let a = actualTotal { return Self.round2(a) }
        if let annual = annualIncome { return Self.round2(annual / 365 * Decimal(days)) }
        if let ind = industryAnnual { return Self.round2(ind / 365 * Decimal(days)) }
        throw PersonalInjuryError.missingLostIncomeBasis
    }

    /// 护理费（按优先级）：日护理费×天 → 护理人年收入÷365×天。天数 ≤0 → 0；二者皆无 → 报错。
    public func nursingFee(ratePerDay: Decimal? = nil, annualIncome: Decimal? = nil, days: Int) throws -> Decimal {
        guard days > 0 else { return 0 }
        if let r = ratePerDay { return Self.round2(r * Decimal(days)) }
        if let annual = annualIncome { return Self.round2(annual / 365 * Decimal(days)) }
        throw PersonalInjuryError.missingNursingBasis
    }

    /// 被扶养人生活费（每人一行金额，按输入顺序）。
    /// 年度份额 = 消费支出 / 该被扶养人的扶养义务人数；各份额之和超过消费支出时同比例压缩。
    public func dependentSupportFee(consumptionBase: Decimal, dependents: [Dependent]) throws -> [Decimal] {
        let shares = dependents.map { consumptionBase / Decimal($0.supporterCount) }
        let totalShare = shares.reduce(Decimal(0), +)
        let capFactor: Decimal = totalShare > consumptionBase ? consumptionBase / totalShare : 1
        var out: [Decimal] = []
        for (i, dep) in dependents.enumerated() {
            let years = Decimal(try dependentYears(age: dep.age, noLaborCapacity: dep.noLaborCapacity))
            out.append(Self.round2(shares[i] * capFactor * years))
        }
        return out
    }
}
