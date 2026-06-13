import Foundation

// MARK: - 人身损害赔偿计算器（忠实 1:1 复刻得理 personal-injury-compensation）
//
// 纯确定性、离线。本文件落地核心算法（伤残系数 / 赔偿年限 / 被扶养人年限）。
// 各赔偿项的组装、各省工资表与全国可支配收入表见 PersonalInjuryEngine.swift。
// 注：分省「可支配收入 / 消费支出 / 农村纯收入」得理包内无表，须由调用方传入（statistics）。

public enum PersonalInjuryError: Error, Equatable {
    case invalidDisabilityLevel
    case emptyDisabilityLevels
    case adultDependentNeedsNoLaborCapacity
    case missingWageData
    case missingLostIncomeBasis
    case missingNursingBasis
    case missingDisposableBase
    case missingConsumptionBase
}

/// 职工平均工资统计口径。丧葬费默认「城镇私营单位」（最低口径）。
public enum WageCaliber: String, Codable, Sendable, CaseIterable {
    case privateUnit      // 城镇私营单位（年薪，⭐默认）
    case fullUnit         // 全口径城镇单位（月薪）
    case nonPrivateUnit   // 城镇非私营单位（年薪）
}

public struct PersonalInjuryCalculator: Sendable {
    public init() {}

    /// 伤残系数。单级 = (11-级)/10；多处 = 主系数 + min(其余系数和×0.1, 0.1)，总封顶 1.0。
    public func disabilityRatio(levels: [Int]) throws -> Decimal {
        guard !levels.isEmpty else { throw PersonalInjuryError.emptyDisabilityLevels }
        for l in levels where l < 1 || l > 10 { throw PersonalInjuryError.invalidDisabilityLevel }
        let ratios = levels.map { Decimal(11 - $0) / 10 }.sorted(by: >)
        let main = ratios[0]
        let othersSum = ratios.dropFirst().reduce(Decimal(0), +)
        let additional = Swift.min(othersSum / 10, Decimal(1) / 10)   // 附加封顶 10%
        return Swift.min(main + additional, 1)                        // 总封顶 100%
    }

    /// 受害人赔偿年限：<60 → 20；60~75 → max(1, 20-(age-60))；>75 → 5。
    public func compensationYears(age: Int) -> Int {
        if age < 60 { return 20 }
        if age <= 75 { return Swift.max(1, 20 - (age - 60)) }
        return 5
    }

    /// 被扶养人年限：<18 → max(0,18-age)；≥18 须无劳动能力，则按受害人年限分段，否则报错。
    public func dependentYears(age: Int, noLaborCapacity: Bool) throws -> Int {
        if age < 18 { return Swift.max(0, 18 - age) }
        guard noLaborCapacity else { throw PersonalInjuryError.adultDependentNeedsNoLaborCapacity }
        return compensationYears(age: age)
    }
}
