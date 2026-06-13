import Testing
import Foundation
@testable import ResponsayCore

// 残疾/死亡赔偿金 + 全国城镇居民人均可支配收入表。
// 测试值取自得理 disposable_income.md 的官方算例（54,188 = 2024 年度数据）。
@Suite("人身损害赔偿计算器 · 赔偿金")
struct PersonalInjuryCompensationTests {
    let calc = PersonalInjuryCalculator()

    @Test("全国可支配收入表（年份=上一统计年度）")
    func national() {
        #expect(calc.nationalDisposable(baseYear: 2024) == 54_188)
        #expect(calc.nationalDisposable(baseYear: 2005) == 10_493)
        #expect(calc.nationalDisposable(baseYear: 1999) == nil)
    }

    @Test("残疾赔偿金 = 基数 × 年限 × 伤残系数（官方算例 108,376）")
    func disability() throws {
        // 60周岁以下、十级伤残、2024 数据：54,188 × 20 × 10% = 108,376
        #expect(try calc.disabilityCompensation(disposableIncome: 54_188, age: 30, levels: [10]) == 108_376)
    }

    @Test("死亡赔偿金 = 基数 × 年限（官方算例 1,083,760 / 812,820）")
    func death() {
        #expect(calc.deathCompensation(disposableIncome: 54_188, age: 30) == 1_083_760) // ×20
        #expect(calc.deathCompensation(disposableIncome: 54_188, age: 65) == 812_820)   // ×15
    }
}
