import Foundation

// MARK: - 诉讼费计算器（《诉讼费用交纳办法》国务院令第481号）
//
// 移植自得理 litigation-fee-calculator（纯确定性、离线、无 API）。全程 `Decimal`，
// 金额四舍五入到分（ROUND_HALF_UP）。幅度收费默认取下限并提示「以当地法院标准为准」。

public enum LitigationFeeError: Error, Equatable {
    case nonPositiveAmount
}

/// 22 类案件 / 申请费类型（第十三、十四条）。
public enum LitigationCaseType: String, Codable, Sendable, CaseIterable {
    case property            // 财产案件受理费 13(一)
    case divorce             // 离婚 13(二)1
    case personality         // 侵害人格权 13(二)2
    case otherNon            // 其他非财产 13(二)3
    case ipNoAmount          // 知产无争议额 13(三)
    case ipWithAmount        // 知产有争议额（同财产）13(三)
    case labor               // 劳动争议 13(四)
    case adminIP             // 商标/专利/海事行政 13(五)
    case adminOther          // 其他行政 13(五)
    case jurisdiction        // 管辖权异议 13(六)
    case enforcement         // 申请执行（有金额）14(一)
    case enforcementNo       // 申请执行（无金额）14(一)
    case preservation        // 保全 14(二)
    case paymentOrder        // 支付令 14(三)
    case publicNotice        // 公示催告 14(四)
    case arbitrationSetAside // 撤销/认定仲裁 14(五)
    case bankruptcy          // 破产 14(六)
    case maritimeFund        // 海事赔偿责任限制基金 14(七)
    case maritimeInjunction  // 海事强制令 14(七)
    case maritimePriority    // 船舶优先权催告 14(七)
    case maritimeClaim       // 海事债权登记 14(七)
    case maritimeAverage     // 共同海损理算 14(七)
}

public struct LitigationFeeResult: Sendable, Equatable {
    public let caseType: LitigationCaseType
    public let total: Decimal
    public let article: String
    public let breakdown: [String]
    public let note: String?
    public let baseFee: Decimal?
    public let extraFee: Decimal?

    public init(caseType: LitigationCaseType, total: Decimal, article: String,
                breakdown: [String] = [], note: String? = nil,
                baseFee: Decimal? = nil, extraFee: Decimal? = nil) {
        self.caseType = caseType
        self.total = total
        self.article = article
        self.breakdown = breakdown
        self.note = note
        self.baseFee = baseFee
        self.extraFee = extraFee
    }
}

public struct LitigationFeeCalculator: Sendable {
    public init() {}

    private struct Tier {
        let lower: Decimal
        let upper: Decimal?   // nil = 顶段（无上限）
        let rate: Decimal
    }

    // 第十三条（一）财产案件：第一段固定 50 元；其后对落入各区间的「超出部分」按费率累加。
    private static let propertyTiers: [Tier] = [
        Tier(lower: 10_000,     upper: 100_000,    rate: dec("0.025")),
        Tier(lower: 100_000,    upper: 200_000,    rate: dec("0.02")),
        Tier(lower: 200_000,    upper: 500_000,    rate: dec("0.015")),
        Tier(lower: 500_000,    upper: 1_000_000,  rate: dec("0.01")),
        Tier(lower: 1_000_000,  upper: 2_000_000,  rate: dec("0.009")),
        Tier(lower: 2_000_000,  upper: 5_000_000,  rate: dec("0.008")),
        Tier(lower: 5_000_000,  upper: 10_000_000, rate: dec("0.007")),
        Tier(lower: 10_000_000, upper: 20_000_000, rate: dec("0.006")),
        Tier(lower: 20_000_000, upper: nil,        rate: dec("0.005")),
    ]

    // 第十四条（一）申请执行费：第一段固定 50 元；其后分段累进。
    private static let enforcementTiers: [Tier] = [
        Tier(lower: 10_000,     upper: 500_000,     rate: dec("0.015")),
        Tier(lower: 500_000,    upper: 5_000_000,   rate: dec("0.01")),
        Tier(lower: 5_000_000,  upper: 10_000_000,  rate: dec("0.005")),
        Tier(lower: 10_000_000, upper: nil,         rate: dec("0.001")),
    ]

    /// 财产案件受理费（第十三条一）。金额须 > 0；≤1万固定 50 元；其后分段累进，总额四舍五入到分。
    public func propertyFee(amount: Decimal) throws -> Decimal {
        try tieredFee(amount: amount, tiers: Self.propertyTiers)
    }

    /// 申请执行费（第十四条一·有金额）。
    public func enforcementFee(amount: Decimal) throws -> Decimal {
        try tieredFee(amount: amount, tiers: Self.enforcementTiers)
    }

    private func tieredFee(amount: Decimal, tiers: [Tier]) throws -> Decimal {
        guard amount > 0 else { throw LitigationFeeError.nonPositiveAmount }
        var fee: Decimal = 50
        if amount <= 10_000 { return fee }
        for tier in tiers where amount > tier.lower {
            let upper = tier.upper ?? amount
            fee += (Swift.min(amount, upper) - tier.lower) * tier.rate
        }
        return Self.round2(fee)
    }

    /// 计算应缴诉讼费 / 申请费。`amount` 用于财产类与执行类；`property` 用于离婚；`damages` 用于人格权。
    public func calculate(type: LitigationCaseType,
                          amount: Decimal = 0,
                          property: Decimal = 0,
                          damages: Decimal = 0,
                          baseFee: Decimal? = nil) throws -> LitigationFeeResult {
        switch type {
        case .property:
            return result(type, try propertyFee(amount: amount))
        case .ipWithAmount:
            return result(type, try propertyFee(amount: amount))
        case .enforcement:
            return result(type, try enforcementFee(amount: amount))
        case .preservation:
            return result(type, preservationFee(amount: amount))
        case .paymentOrder:
            return result(type, Self.round2(try propertyFee(amount: amount) / 3))
        case .bankruptcy:
            let half = Self.round2(try propertyFee(amount: amount) / 2)
            return result(type, Swift.min(half, 300_000))
        case .divorce:
            let base = baseFee ?? 50
            let extra = property > 200_000 ? Self.round2((property - 200_000) * dec("0.005")) : 0
            return result(type, base + extra, base: base, extra: extra)
        case .personality:
            let base = baseFee ?? 100
            var extra: Decimal = 0
            if damages > 50_000 { extra += Self.round2((Swift.min(damages, 100_000) - 50_000) * dec("0.01")) }
            if damages > 100_000 { extra += Self.round2((damages - 100_000) * dec("0.005")) }
            return result(type, base + extra, base: base, extra: extra)
        case .otherNon:            return result(type, 50)
        case .ipNoAmount:          return result(type, 500)
        case .labor:               return result(type, 10)
        case .adminIP:             return result(type, 100)
        case .adminOther:          return result(type, 50)
        case .jurisdiction:        return result(type, 50)
        case .enforcementNo:       return result(type, 50)
        case .publicNotice:        return result(type, 100)
        case .arbitrationSetAside: return result(type, 400)
        case .maritimeFund, .maritimeInjunction, .maritimePriority,
             .maritimeClaim, .maritimeAverage:
            return result(type, 1_000)
        }
    }

    // 第十四条（二）保全费：≤1000(或不涉财产数额)固定30；1000~10万 30+(额-1000)×1%；
    // >10万 30+990+(额-10万)×0.5%；硬上限 5000。
    private func preservationFee(amount: Decimal) -> Decimal {
        let fee: Decimal
        if amount <= 1_000 {
            fee = 30
        } else if amount <= 100_000 {
            fee = 30 + (amount - 1_000) * dec("0.01")
        } else {
            fee = 30 + 990 + (amount - 100_000) * dec("0.005")
        }
        return Swift.min(Self.round2(fee), 5_000)
    }

    private func result(_ type: LitigationCaseType, _ total: Decimal,
                        base: Decimal? = nil, extra: Decimal? = nil) -> LitigationFeeResult {
        LitigationFeeResult(caseType: type, total: total, article: Self.article(for: type),
                            note: Self.note(for: type), baseFee: base, extraFee: extra)
    }

    static func article(for type: LitigationCaseType) -> String {
        let prefix = "《诉讼费用交纳办法》"
        switch type {
        case .property:            return prefix + "第十三条第（一）项"
        case .divorce:             return prefix + "第十三条第（二）项第1目"
        case .personality:         return prefix + "第十三条第（二）项第2目"
        case .otherNon:            return prefix + "第十三条第（二）项第3目"
        case .ipNoAmount, .ipWithAmount: return prefix + "第十三条第（三）项"
        case .labor:               return prefix + "第十三条第（四）项"
        case .adminIP, .adminOther: return prefix + "第十三条第（五）项"
        case .jurisdiction:        return prefix + "第十三条第（六）项"
        case .enforcement, .enforcementNo: return prefix + "第十四条第（一）项"
        case .preservation:        return prefix + "第十四条第（二）项"
        case .paymentOrder:        return prefix + "第十四条第（三）项"
        case .publicNotice:        return prefix + "第十四条第（四）项"
        case .arbitrationSetAside: return prefix + "第十四条第（五）项"
        case .bankruptcy:          return prefix + "第十四条第（六）项"
        case .maritimeFund, .maritimeInjunction, .maritimePriority,
             .maritimeClaim, .maritimeAverage:
            return prefix + "第十四条第（七）项"
        }
    }

    // 幅度收费默认取下限，提示以当地法院标准为准（非全国统一固定额）。
    static func note(for type: LitigationCaseType) -> String? {
        switch type {
        case .otherNon:     return "每件50~100元；默认取下限50元，以当地法院标准为准。"
        case .ipNoAmount:   return "每件500~1000元；默认取下限500元，以当地法院标准为准。"
        case .jurisdiction: return "异议不成立时每件50~100元；默认取下限50元，以当地法院标准为准。"
        case .enforcementNo: return "无执行金额时每件50~500元；默认取下限50元。"
        case .preservation: return "不超过1000元或不涉及财产数额的每件30元；最高不超过5000元。"
        case .paymentOrder: return "按财产案件受理费标准的 1/3 交纳。"
        case .bankruptcy:   return "按财产案件受理费标准减半交纳，最高不超过30万元。"
        case .divorce:      return "基础费50~300元，以当地法院标准为准；财产超20万部分按0.5%另计。"
        case .personality:  return "基础费100~500元，以当地法院标准为准；赔偿额超5万部分1%、超10万部分0.5%另计。"
        case .maritimeFund: return "法定区间1000~10000元；默认取下限1000元。"
        case .maritimeInjunction, .maritimePriority: return "法定区间1000~5000元；默认取下限1000元。"
        default:            return nil
        }
    }

    /// 四舍五入到分（0.01，HALF_UP）。金额均为正，`.plain` 即四舍五入。
    static func round2(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 2, .plain)
        return result
    }

}

/// 精确十进制字面量（避免浮点字面量误差）。
private func dec(_ s: String) -> Decimal { Decimal(string: s)! }
