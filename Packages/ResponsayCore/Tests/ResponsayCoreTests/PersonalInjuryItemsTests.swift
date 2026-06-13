import Testing
import Foundation
@testable import ResponsayCore

// 误工/护理/营养/住院伙食/被扶养人生活费等赔偿项（含被扶养人份额封顶）。
@Suite("人身损害赔偿计算器 · 各赔偿项")
struct PersonalInjuryItemsTests {
    let calc = PersonalInjuryCalculator()

    @Test("营养费 / 住院伙食补助（单价×天数，默认50/100）")
    func nutritionAndMeal() {
        #expect(calc.nutritionFee(days: 30) == 1_500)              // 50×30
        #expect(calc.nutritionFee(ratePerDay: 80, days: 30) == 2_400)
        #expect(calc.nutritionFee(days: 0) == 0)
        #expect(calc.hospitalMealFee(days: 10) == 1_000)           // 100×10
    }

    @Test("误工费三选一：实际总额直取 / 年收入÷365×天 / 行业参照")
    func lostIncome() throws {
        #expect(try calc.lostIncomeFee(actualTotal: 5_000, days: 30) == 5_000)  // 总额直取
        #expect(try calc.lostIncomeFee(annualIncome: 73_000, days: 30) == 6_000) // 200/天×30
        #expect(try calc.lostIncomeFee(annualIncome: 73_000, days: 0) == 0)
        #expect(throws: PersonalInjuryError.missingLostIncomeBasis) {
            _ = try calc.lostIncomeFee(days: 30)
        }
    }

    @Test("护理费二选一：日护理费×天 / 护理人年收入÷365×天")
    func nursing() throws {
        #expect(try calc.nursingFee(ratePerDay: 150, days: 30) == 4_500)
        #expect(try calc.nursingFee(annualIncome: 73_000, days: 30) == 6_000)
        #expect(throws: PersonalInjuryError.missingNursingBasis) {
            _ = try calc.nursingFee(days: 30)
        }
    }

    @Test("被扶养人生活费：年度份额合计超消费支出时同比例压缩")
    func dependentSupport() throws {
        // 单个被扶养人，2 个扶养义务人 → 年度份额 30000/2=15000；未超基数；×8年
        #expect(try calc.dependentSupportFee(consumptionBase: 30_000,
                    dependents: [Dependent(age: 10, supporterCount: 2)]) == [120_000])
        // 两个被扶养人各 1 义务人 → 份额各 30000，合计 60000 > 30000 → cap 0.5；各 30000×0.5×8=120000
        #expect(try calc.dependentSupportFee(consumptionBase: 30_000,
                    dependents: [Dependent(age: 10), Dependent(age: 10)]) == [120_000, 120_000])
    }
}
