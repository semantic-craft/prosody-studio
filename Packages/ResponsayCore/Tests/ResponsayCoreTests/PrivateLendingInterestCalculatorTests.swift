import Testing
import Foundation
@testable import ResponsayCore

// 民间借贷利息计算器（忠实 1:1 复刻得理 private-lending-interest-calculator）。
// 按日单利、365 天口径、逐段四舍五入到分；利率上限按段起点的 regime 判定。
@Suite("民间借贷利息计算器 · 基元")
struct PrivateLendingInterestPrimitivesTests {
    let calc = PrivateLendingInterestCalculator()

    private func ymd(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }

    // MARK: - LPR 查表（取 ≤ 目标日期的最近一期；早于首期回退首期 4.25%）

    @Test("LPR 精确命中报价日")
    func lprExact() {
        #expect(calc.findLPR(asOf: ymd(2020, 8, 20)) == Decimal(string: "3.85"))
    }

    @Test("LPR 取 ≤ 目标日期的最近一期")
    func lprFloor() {
        #expect(calc.findLPR(asOf: ymd(2024, 12, 31)) == Decimal(string: "3.10")) // 2024-12-20 期
        #expect(calc.findLPR(asOf: ymd(2023, 9, 1)) == Decimal(string: "3.45"))   // 2023-08-21 期
    }

    @Test("早于首期回退首期 4.25%")
    func lprBeforeFirst() {
        #expect(calc.findLPR(asOf: ymd(2019, 1, 1)) == Decimal(string: "4.25"))
    }

    // MARK: - 单段利息（本金 × 年利率/100 × 天数/365，四舍五入到分）

    @Test("整年利息")
    func interestFullYear() {
        #expect(calc.annualInterest(principal: 100_000, annualRatePercent: 12, days: 365) == 12_000)
    }

    @Test("按日折算并四舍五入到分")
    func interestPartial() {
        // 100000 × 12% × 30/365 = 986.3013… → 986.30
        #expect(calc.annualInterest(principal: 100_000, annualRatePercent: 12, days: 30)
                == Decimal(string: "986.30"))
    }

    @Test("零利率/零天数 → 0")
    func interestZero() {
        #expect(calc.annualInterest(principal: 100_000, annualRatePercent: 0, days: 365) == 0)
        #expect(calc.annualInterest(principal: 100_000, annualRatePercent: 12, days: 0) == 0)
    }

    // MARK: - 利率上限（按段起点 regime）

    @Test("2015~2020 段封顶 24%")
    func cap24() throws {
        #expect(try calc.capRate(segmentStart: ymd(2016, 1, 1), loanDate: ymd(2016, 1, 1),
                                 legacyBaseRate: nil) == 24)
    }

    @Test("2020-08-20 后封顶 = 借款日 LPR×4")
    func capLpr4() throws {
        // loanDate 2021-01-01 → LPR(2021-01-01)=3.85 → ×4 = 15.40
        #expect(try calc.capRate(segmentStart: ymd(2021, 1, 1), loanDate: ymd(2021, 1, 1),
                                 legacyBaseRate: nil) == Decimal(string: "15.40"))
    }

    @Test("2015 前封顶 = 银行同期利率×4；缺 legacy 则报错")
    func capLegacy() throws {
        #expect(try calc.capRate(segmentStart: ymd(2014, 1, 1), loanDate: ymd(2014, 1, 1),
                                 legacyBaseRate: 6) == 24)
        #expect(throws: PrivateLendingError.missingLegacyBaseRate) {
            _ = try calc.capRate(segmentStart: ymd(2014, 1, 1), loanDate: ymd(2014, 1, 1),
                                 legacyBaseRate: nil)
        }
    }
}
