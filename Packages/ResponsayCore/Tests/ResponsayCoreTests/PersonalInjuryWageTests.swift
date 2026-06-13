import Testing
import Foundation
@testable import ResponsayCore

// 各省职工平均工资表（3 口径）+ 丧葬费。测试值取自 provincial_avg_wage.md 源数据与官方算例。
@Suite("人身损害赔偿计算器 · 各省工资与丧葬费")
struct PersonalInjuryWageTests {
    let calc = PersonalInjuryCalculator()

    @Test("各省工资查表（口径 + 省名归一化 + 缺数据）")
    func wageLookup() {
        #expect(calc.provinceWage(province: "北京市", baseYear: 2024, caliber: .privateUnit) == 106_905)
        #expect(calc.provinceWage(province: "北京市", baseYear: 2024, caliber: .nonPrivateUnit) == 224_608)
        #expect(calc.provinceWage(province: "北京", baseYear: 2024, caliber: .fullUnit) == 12_049)
        #expect(calc.provinceWage(province: "上海市", baseYear: 2024, caliber: .privateUnit) == 113_914)
        #expect(calc.provinceWage(province: "内蒙古自治区", baseYear: 2024, caliber: .privateUnit) == 59_217)
        // 河北全口径 2016 = — （缺）
        #expect(calc.provinceWage(province: "河北省", baseYear: 2016, caliber: .fullUnit) == nil)
    }

    @Test("丧葬费 = 月均工资 × 6（全口径=月薪直接用；年薪÷12）")
    func funeral() throws {
        // 全口径：北京2024 = 12049元/月 × 6 = 72294
        #expect(try calc.funeralFee(province: "北京", baseYear: 2024, caliber: .fullUnit) == 72_294)
        // 私营（默认，年薪）：北京2024 = 106905/12 × 6 = 53452.50（全精度，doc 算例 53454 系月薪先取整）
        #expect(try calc.funeralFee(province: "北京市", baseYear: 2024) == Decimal(string: "53452.50"))
        // 缺数据 → 报错
        #expect(throws: PersonalInjuryError.missingWageData) {
            _ = try calc.funeralFee(province: "河北省", baseYear: 2016, caliber: .fullUnit)
        }
    }
}
