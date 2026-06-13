import Foundation

// MARK: - 人身损害赔偿：赔偿金组装 + 全国可支配收入表
//
// 「两者结合」：内置全国城镇居民人均可支配收入表（得理包内有）；分省可支配收入/消费支出/
// 农村纯收入得理包内无表，由调用方传入（statistics override）。各省职工平均工资表（丧葬费/
// 误工费用）后续切片接入。

extension PersonalInjuryCalculator {

    /// 全国城镇居民人均可支配收入（年份 = 一审法庭辩论终结时的上一统计年度 → 元/年）。
    /// 来源：国家统计局历年公告（得理 disposable_income.md）。受诉法院为省/市级时应优先用当地数据。
    public static let nationalDisposableIncome: [Int: Decimal] = [
        2005: 10_493, 2006: 11_620, 2007: 13_603, 2008: 15_549, 2009: 16_901,
        2010: 18_779, 2011: 21_427, 2012: 24_127, 2013: 26_467, 2014: 28_844,
        2015: 31_195, 2016: 33_616, 2017: 36_396, 2018: 39_251, 2019: 42_359,
        2020: 43_834, 2021: 47_412, 2022: 49_283, 2023: 51_821, 2024: 54_188,
        2025: 56_502,
    ]

    /// 全国可支配收入兜底查询（分省数据须由调用方提供）。
    public func nationalDisposable(baseYear: Int) -> Decimal? {
        Self.nationalDisposableIncome[baseYear]
    }

    /// 残疾赔偿金 = 城镇居民人均可支配收入 × 赔偿年限 × 伤残系数。
    public func disabilityCompensation(disposableIncome: Decimal, age: Int, levels: [Int]) throws -> Decimal {
        let years = Decimal(compensationYears(age: age))
        let ratio = try disabilityRatio(levels: levels)
        return Self.round2(disposableIncome * years * ratio)
    }

    /// 死亡赔偿金 = 城镇居民人均可支配收入 × 赔偿年限（无伤残系数）。
    public func deathCompensation(disposableIncome: Decimal, age: Int) -> Decimal {
        Self.round2(disposableIncome * Decimal(compensationYears(age: age)))
    }

    /// 四舍五入到分（0.01，HALF_UP）。
    static func round2(_ value: Decimal) -> Decimal {
        var input = value; var result = Decimal()
        NSDecimalRound(&result, &input, 2, .plain)
        return result
    }
}
