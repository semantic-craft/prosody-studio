import Testing
import Foundation
@testable import ResponsayCore

// 利息分段引擎：借期内/逾期分段、利率上限、5 级还款冲抵、无息/砍头息/截断警告。
@Suite("民间借贷利息计算器 · 引擎")
struct PrivateLendingInterestEngineTests {
    let calc = PrivateLendingInterestCalculator()

    private func ymd(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }

    @Test("借期内整年 12% → 利息 12000")
    func withinOnly() throws {
        var c = PrivateLendingCase(principal: 100_000, loanDate: ymd(2021, 1, 1), asOf: ymd(2022, 1, 1))
        c.rate = 12
        let r = try calc.calculate(c)
        #expect(r.withinInterest == 12_000)
        #expect(r.outstandingPrincipal == 100_000)
        #expect(r.totalOutstanding == 112_000)
    }

    @Test("约定利率超 LPR×4 上限被截断 + 警告")
    func capTruncation() throws {
        var c = PrivateLendingCase(principal: 100_000, loanDate: ymd(2021, 1, 1), asOf: ymd(2022, 1, 1))
        c.rate = 20  // cap = LPR(2021-01-01)=3.85 ×4 = 15.40%
        let r = try calc.calculate(c)
        #expect(r.withinInterest == 15_400)  // 100000 × 15.40% × 365/365
        #expect(r.warnings.contains { $0.contains("上限") })
    }

    @Test("未约定利率按无息处理")
    func noInterest() throws {
        let c = PrivateLendingCase(principal: 100_000, loanDate: ymd(2021, 1, 1), asOf: ymd(2022, 1, 1))
        let r = try calc.calculate(c)
        #expect(r.withinInterest == 0)
        #expect(r.totalOutstanding == 100_000)
        #expect(r.assumptions.contains { $0.contains("无息") })
    }

    @Test("还款冲抵：无息时直接冲本金")
    func repaymentToPrincipal() throws {
        var c = PrivateLendingCase(principal: 100_000, loanDate: ymd(2021, 1, 1), asOf: ymd(2022, 1, 1))
        c.repayments = [Repayment(date: ymd(2021, 7, 1), amount: 50_000)]
        let r = try calc.calculate(c)
        #expect(r.outstandingPrincipal == 50_000)
        #expect(r.totalOutstanding == 50_000)
    }

    @Test("借期内+逾期：两段都算，逾期利率封顶，合计=各项之和")
    func withinAndOverdue() throws {
        var c = PrivateLendingCase(principal: 100_000, loanDate: ymd(2021, 1, 1), asOf: ymd(2022, 1, 1))
        c.rate = 10
        c.loanEnd = ymd(2021, 7, 1)  // 未给逾期起算日 → 派生 = 到期日
        c.overdueRate = 18           // 超上限 15.40 → 截断
        let r = try calc.calculate(c)
        #expect(r.withinInterest > 0)
        #expect(r.overdueInterest > 0)
        #expect(r.totalOutstanding
                == 100_000 + r.withinInterest + r.overdueInterest + r.penalty + r.fees)
    }

    @Test("砍头息：合同本金>实际到账 → 警告，本金按实际")
    func skimming() throws {
        var c = PrivateLendingCase(principal: 100_000, loanDate: ymd(2021, 1, 1), asOf: ymd(2022, 1, 1))
        c.contractPrincipal = 120_000
        let r = try calc.calculate(c)
        #expect(r.outstandingPrincipal == 100_000)
        #expect(r.warnings.contains { $0.contains("砍头息") })
    }

    @Test("校验：本金≤0 / 合同本金<本金 / asOf<借款日 / 2015前缺legacy")
    func validation() {
        #expect(throws: PrivateLendingError.nonPositivePrincipal) {
            _ = try calc.calculate(PrivateLendingCase(principal: 0, loanDate: ymd(2021, 1, 1), asOf: ymd(2022, 1, 1)))
        }
        #expect(throws: PrivateLendingError.asOfBeforeLoan) {
            _ = try calc.calculate(PrivateLendingCase(principal: 100, loanDate: ymd(2021, 6, 1), asOf: ymd(2021, 1, 1)))
        }
        #expect(throws: PrivateLendingError.missingLegacyBaseRate) {
            _ = try calc.calculate(PrivateLendingCase(principal: 100, loanDate: ymd(2014, 1, 1), asOf: ymd(2015, 1, 1)))
        }
    }
}
