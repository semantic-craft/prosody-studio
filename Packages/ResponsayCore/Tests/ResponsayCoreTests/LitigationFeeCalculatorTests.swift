import Testing
import Foundation
@testable import ResponsayCore

// 诉讼费计算器（《诉讼费用交纳办法》国务院令第481号 第十三、十四条）。
// 移植自得理 litigation-fee-calculator（纯确定性、Decimal、ROUND_HALF_UP 到 0.01）。
@Suite("诉讼费计算器")
struct LitigationFeeCalculatorTests {
    let calc = LitigationFeeCalculator()

    // MARK: - 财产案件受理费（第十三条一 · 分段累进）

    @Test("不超过1万元固定50元（含边界）")
    func propertyFloor() throws {
        #expect(try calc.propertyFee(amount: 10_000) == 50)
        #expect(try calc.propertyFee(amount: 5_000) == 50)
        #expect(try calc.propertyFee(amount: 1) == 50)
    }

    @Test("150万元 → 18300元（分段累进验证例）")
    func property150w() throws {
        // 50 + 9万×2.5% + 10万×2% + 30万×1.5% + 50万×1% + 50万×0.9%
        // = 50 + 2250 + 2000 + 4500 + 5000 + 4500 = 18300
        #expect(try calc.propertyFee(amount: 1_500_000) == 18_300)
    }

    @Test("金额必须大于0，否则报错")
    func propertyNonPositive() {
        #expect(throws: LitigationFeeError.nonPositiveAmount) {
            _ = try calc.propertyFee(amount: 0)
        }
    }

    // MARK: - 申请执行费（第十四条一 · 分段累进）

    @Test("执行费 150万 → 17400元")
    func enforcement150w() throws {
        // 50 + (50万-1万)×1.5% + (150万-50万)×1% = 50 + 7350 + 10000 = 17400
        let r = try calc.calculate(type: .enforcement, amount: 1_500_000)
        #expect(r.total == 17_400)
    }

    // MARK: - 申请保全措施费（第十四条二 · 三分支 + 5000封顶）

    @Test("保全费三分支 + 5000封顶")
    func preservation() throws {
        #expect(try calc.calculate(type: .preservation, amount: 1_000).total == 30)
        #expect(try calc.calculate(type: .preservation, amount: 50_000).total == 520)     // 30 + 49000×1%
        #expect(try calc.calculate(type: .preservation, amount: 2_000_000).total == 5_000) // 30+990+9500=10520→封顶5000
    }

    // MARK: - 派生费（支付令÷3 · 破产÷2 上限30万）

    @Test("支付令 = 财产受理费的 1/3")
    func paymentOrder() throws {
        #expect(try calc.calculate(type: .paymentOrder, amount: 1_500_000).total == 6_100) // 18300/3
    }

    @Test("破产 = 财产受理费减半，上限30万")
    func bankruptcy() throws {
        #expect(try calc.calculate(type: .bankruptcy, amount: 1_500_000).total == 9_150)   // 18300/2
        #expect(try calc.calculate(type: .bankruptcy, amount: 200_000_000).total == 300_000) // 封顶
    }

    // MARK: - 离婚（第十三条二1 · 基础费 + 财产超20万部分0.5%）

    @Test("离婚案件基础费 + 财产分割超额")
    func divorce() throws {
        #expect(try calc.calculate(type: .divorce, property: 100_000).total == 50)          // 仅基础费下限
        #expect(try calc.calculate(type: .divorce, property: 300_000).total == 550)          // 50 + 10万×0.5%
        #expect(try calc.calculate(type: .divorce, property: 300_000, baseFee: 300).total == 800) // 覆盖基础费
    }

    // MARK: - 人格权（第十三条二2 · 基础费 + 5万~10万1% + 超10万0.5%）

    @Test("侵害人格权案件基础费 + 两段超额")
    func personality() throws {
        #expect(try calc.calculate(type: .personality, damages: 0).total == 100)            // 仅基础费下限
        // 100 + (10万-5万)×1% + (15万-10万)×0.5% = 100 + 500 + 250 = 850
        #expect(try calc.calculate(type: .personality, damages: 150_000).total == 850)
    }

    // MARK: - 知识产权（有争议额 = 财产案件）

    @Test("知产有争议额按财产案件算")
    func ipWithAmount() throws {
        #expect(try calc.calculate(type: .ipWithAmount, amount: 1_500_000).total == 18_300)
    }

    // MARK: - 固定费 / 幅度取下限

    @Test("固定费与幅度下限")
    func fixedFees() throws {
        #expect(try calc.calculate(type: .labor).total == 10)
        #expect(try calc.calculate(type: .otherNon).total == 50)
        #expect(try calc.calculate(type: .ipNoAmount).total == 500)
        #expect(try calc.calculate(type: .adminIP).total == 100)
        #expect(try calc.calculate(type: .adminOther).total == 50)
        #expect(try calc.calculate(type: .jurisdiction).total == 50)
        #expect(try calc.calculate(type: .enforcementNo).total == 50)
        #expect(try calc.calculate(type: .publicNotice).total == 100)
        #expect(try calc.calculate(type: .arbitrationSetAside).total == 400)
        #expect(try calc.calculate(type: .maritimeFund).total == 1_000)
        #expect(try calc.calculate(type: .maritimeInjunction).total == 1_000)
        #expect(try calc.calculate(type: .maritimePriority).total == 1_000)
        #expect(try calc.calculate(type: .maritimeClaim).total == 1_000)
        #expect(try calc.calculate(type: .maritimeAverage).total == 1_000)
    }

    @Test("结果带法条引用")
    func resultArticle() throws {
        let r = try calc.calculate(type: .property, amount: 1_500_000)
        #expect(r.article.contains("第十三条"))
        #expect(r.total == 18_300)
    }
}
