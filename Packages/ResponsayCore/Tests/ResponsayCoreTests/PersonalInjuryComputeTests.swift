import Testing
import Foundation
@testable import ResponsayCore

// 整案组装：按法定顺序拼装各赔偿项 → 明细 + 合计。
@Suite("人身损害赔偿计算器 · 整案组装")
struct PersonalInjuryComputeTests {
    let calc = PersonalInjuryCalculator()

    @Test("死亡案件：死亡赔偿金 + 丧葬费 + 实报项")
    func deathCase() throws {
        var c = PersonalInjuryCase(caseType: .death, victimAge: 30, province: "北京市", baseYear: 2024)
        c.disabilityDeathBase = 54_188   // 城镇可支配收入
        c.medicalExpense = 10_000
        let r = try calc.compute(c)
        // 1,083,760 + 53,452.50 + 10,000
        #expect(r.total == Decimal(string: "1147212.50"))
        #expect(r.lines.contains { $0.item == "死亡赔偿金" && $0.amount == 1_083_760 })
        #expect(r.lines.contains { $0.item == "丧葬费" && $0.amount == Decimal(string: "53452.50") })
        #expect(r.lines.contains { $0.item == "医疗费" && $0.amount == 10_000 })
    }

    @Test("伤残案件：残疾赔偿金 + 营养费")
    func injuryCase() throws {
        var c = PersonalInjuryCase(caseType: .injury, victimAge: 30, province: "北京市", baseYear: 2024)
        c.disabilityDeathBase = 54_188
        c.disabilityLevels = [10]
        c.nutritionDays = 30
        let r = try calc.compute(c)
        #expect(r.total == 109_876)  // 108,376 + 1,500
        #expect(r.lines.contains { $0.item == "残疾赔偿金" && $0.amount == 108_376 })
        // 伤残案件不计丧葬费
        #expect(!r.lines.contains { $0.item == "丧葬费" })
    }
}
