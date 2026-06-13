import Foundation

// MARK: - 民间借贷利息计算器（忠实 1:1 复刻得理 private-lending-interest-calculator）
//
// 纯确定性、离线、无 API。按日单利、365 天口径、逐段四舍五入到分（ROUND_HALF_UP）。
// 利率上限按「段起点」的 regime 判定：<2015-09-01 银行同期×4；2015~2020 封顶 24%；
// ≥2020-08-20 合同成立时 1 年期 LPR×4。
// 注：源脚本未实现「两线三区」(24%~36% 自然债务) 与「复利本息和上限」——本移植同样不做，
// 仅在 calculate 阶段以 warning 标注（见后续切片）。

public enum PrivateLendingError: Error, Equatable {
    case nonPositivePrincipal
    case contractLessThanPrincipal
    case asOfBeforeLoan
    case loanEndBeforeLoan
    case overdueBeforeLoan
    case invalidRepayment
    case missingLegacyBaseRate
}

public struct PrivateLendingInterestCalculator: Sendable {
    public init() {}

    // 1 年期 LPR 报价（自 2019-08-20 起每月发布），来源：全国银行间同业拆借中心。升序。
    // ⚠️ 含未来日期占位数据（2025+），真实值需 live 核对。
    private static let lprRaw = """
    2019-08-20 4.25
    2019-09-20 4.20
    2019-10-21 4.20
    2019-11-20 4.15
    2019-12-20 4.15
    2020-01-20 4.15
    2020-02-20 4.05
    2020-03-20 4.05
    2020-04-20 3.85
    2020-05-20 3.85
    2020-06-22 3.85
    2020-07-20 3.85
    2020-08-20 3.85
    2020-09-21 3.85
    2020-10-20 3.85
    2020-11-20 3.85
    2020-12-21 3.85
    2021-01-20 3.85
    2021-02-22 3.85
    2021-03-22 3.85
    2021-04-20 3.85
    2021-05-20 3.85
    2021-06-21 3.85
    2021-07-20 3.85
    2021-08-20 3.85
    2021-09-22 3.85
    2021-10-20 3.85
    2021-11-22 3.85
    2021-12-20 3.80
    2022-01-20 3.70
    2022-02-21 3.70
    2022-03-21 3.70
    2022-04-20 3.70
    2022-05-20 3.70
    2022-06-20 3.70
    2022-07-20 3.70
    2022-08-22 3.65
    2022-09-20 3.65
    2022-10-20 3.65
    2022-11-21 3.65
    2022-12-20 3.65
    2023-01-20 3.65
    2023-02-20 3.65
    2023-03-20 3.65
    2023-04-20 3.65
    2023-05-22 3.65
    2023-06-20 3.55
    2023-07-20 3.55
    2023-08-21 3.45
    2023-09-20 3.45
    2023-10-20 3.45
    2023-11-20 3.45
    2023-12-20 3.45
    2024-01-22 3.45
    2024-02-20 3.45
    2024-03-20 3.45
    2024-04-22 3.45
    2024-05-20 3.45
    2024-06-20 3.45
    2024-07-22 3.35
    2024-08-20 3.35
    2024-09-20 3.35
    2024-10-21 3.10
    2024-11-20 3.10
    2024-12-20 3.10
    2025-01-20 3.10
    2025-02-20 3.10
    2025-03-20 3.10
    2025-04-21 3.10
    2025-05-20 3.00
    2025-06-20 3.00
    2025-07-21 3.00
    2025-08-20 3.00
    2025-09-22 3.00
    2025-10-20 3.00
    2025-11-20 3.00
    2025-12-22 3.00
    2026-01-20 3.00
    2026-02-24 3.00
    2026-03-20 3.00
    """

    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    static func parseDate(_ s: String) -> Date {
        let p = s.split(separator: "-").compactMap { Int($0) }
        var dc = DateComponents(); dc.year = p[0]; dc.month = p[1]; dc.day = p[2]
        return calendar.date(from: dc)!
    }

    /// 升序 [(报价日期, 1年期LPR%)]。
    static let lprEntries: [(date: Date, rate: Decimal)] = {
        lprRaw.split(separator: "\n").map { line in
            let f = line.split(separator: " ")
            return (parseDate(String(f[0])), Decimal(string: String(f[1]))!)
        }
    }()

    static let date2015 = parseDate("2015-09-01")
    static let date2020 = parseDate("2020-08-20")

    /// 两日期间隔天数（算头不算尾）。
    static func daysBetween(_ a: Date, _ b: Date) -> Int {
        calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    /// 均未约定逾期利率时的默认逾期利率（按段起点）：<2015 银行同期；2015~2020 = 6%；≥2020 = 逾期当时 LPR。
    func defaultOverdueRate(segmentStart: Date, legacyBaseRate: Decimal?) throws -> Decimal {
        if segmentStart < Self.date2015 {
            guard let base = legacyBaseRate else { throw PrivateLendingError.missingLegacyBaseRate }
            return base
        } else if segmentStart < Self.date2020 {
            return 6
        } else {
            return findLPR(asOf: segmentStart)
        }
    }

    /// 取 ≤ 目标日期的最近一期 LPR；早于首期（2019-08-20）回退首期 4.25%。
    public func findLPR(asOf: Date) -> Decimal {
        var rate = Self.lprEntries.first!.rate
        for e in Self.lprEntries where e.date <= asOf { rate = e.rate }
        return rate
    }

    /// 单段利息 = 本金 × 年利率/100 × 天数/365，四舍五入到分。本金/利率/天数任一 ≤0 → 0。
    public func annualInterest(principal: Decimal, annualRatePercent: Decimal, days: Int) -> Decimal {
        guard principal > 0, annualRatePercent > 0, days > 0 else { return 0 }
        let raw = principal * (annualRatePercent / 100) * Decimal(days) / 365
        return Self.round2(raw)
    }

    /// 利率上限（按段起点 regime）。<2015-09-01 银行同期×4（缺 legacy 报错）；
    /// 2015~2020 封顶 24%；≥2020-08-20 合同成立时 LPR×4。
    public func capRate(segmentStart: Date, loanDate: Date, legacyBaseRate: Decimal?) throws -> Decimal {
        if segmentStart < Self.date2015 {
            guard let base = legacyBaseRate else { throw PrivateLendingError.missingLegacyBaseRate }
            return base * 4
        } else if segmentStart < Self.date2020 {
            return 24
        } else {
            return findLPR(asOf: loanDate) * 4
        }
    }

    /// 四舍五入到分（0.01，HALF_UP）。
    static func round2(_ value: Decimal) -> Decimal {
        var input = value; var result = Decimal()
        NSDecimalRound(&result, &input, 2, .plain)
        return result
    }
}
