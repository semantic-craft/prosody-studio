import Testing
import Foundation
@testable import ResponsayCore

// 人身损害赔偿计算器（忠实 1:1 复刻得理 personal-injury-compensation）。
// 本套测试覆盖核心算法：伤残系数、赔偿年限、被扶养人年限。
@Suite("人身损害赔偿计算器 · 系数与年限")
struct PersonalInjuryHelpersTests {
    let calc = PersonalInjuryCalculator()

    @Test("单一伤残系数 = (11-级)/10")
    func singleRatio() throws {
        #expect(try calc.disabilityRatio(levels: [1]) == 1)
        #expect(try calc.disabilityRatio(levels: [10]) == Decimal(string: "0.1"))
        #expect(try calc.disabilityRatio(levels: [6]) == Decimal(string: "0.5"))
    }

    @Test("多处伤残：主系数 + 附加(其余求和×0.1)，附加封顶10%、总封顶100%")
    func multiRatio() throws {
        // 5/6/7 级 → 0.6 + min((0.5+0.4)×0.1, 0.1) = 0.6 + 0.09 = 0.69
        #expect(try calc.disabilityRatio(levels: [5, 6, 7]) == Decimal(string: "0.69"))
        // 1/2 级 → 1.0 + 0.09 = 1.09 → 总封顶 1.0
        #expect(try calc.disabilityRatio(levels: [1, 2]) == 1)
    }

    @Test("非法等级 / 空 → 报错")
    func ratioInvalid() {
        #expect(throws: PersonalInjuryError.invalidDisabilityLevel) {
            _ = try calc.disabilityRatio(levels: [0])
        }
        #expect(throws: PersonalInjuryError.invalidDisabilityLevel) {
            _ = try calc.disabilityRatio(levels: [11])
        }
        #expect(throws: PersonalInjuryError.emptyDisabilityLevels) {
            _ = try calc.disabilityRatio(levels: [])
        }
    }

    @Test("赔偿年限按年龄分段（<60→20；60~75 递减；>75→5）")
    func compYears() {
        #expect(calc.compensationYears(age: 30) == 20)
        #expect(calc.compensationYears(age: 60) == 20)
        #expect(calc.compensationYears(age: 70) == 10)
        #expect(calc.compensationYears(age: 75) == 5)
        #expect(calc.compensationYears(age: 80) == 5)
    }

    @Test("被扶养人年限（未成年至18；成年需无劳动能力，否则报错）")
    func depYears() throws {
        #expect(try calc.dependentYears(age: 10, noLaborCapacity: false) == 8)
        #expect(try calc.dependentYears(age: 16, noLaborCapacity: false) == 2)
        #expect(try calc.dependentYears(age: 18, noLaborCapacity: true) == 20)
        #expect(try calc.dependentYears(age: 80, noLaborCapacity: true) == 5)
        #expect(throws: PersonalInjuryError.adultDependentNeedsNoLaborCapacity) {
            _ = try calc.dependentYears(age: 20, noLaborCapacity: false)
        }
    }
}
