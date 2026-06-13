import Testing
import Foundation
@testable import ResponsayCore

@Suite("Legal Calculator Engine Tests")
struct LegalCalculatorEngineTests {
    
    @Test("Test Labor Compensation - Standard N")
    func testLaborCompensationStandardN() {
        let params = LegalCalculatorPayloads.LaborCompensationParams(
            terminationType: .mutualAgreement,
            startDate: "2020-01-01",
            endDate: "2021-01-01",
            averageMonthlySalary: 10000.0,
            lastMonthSalary: nil,
            unusedAnnualLeaveDays: 0,
            missingInfo: nil
        )
        
        let report = LegalCalculatorEngine.calculateLaborCompensation(params: params)
        #expect(report.contains("1.0 × 10000.00 × 1.0"))
        #expect(report.contains("总计金额: 10000.00 元"))
    }
    
    @Test("Test Labor Compensation - 2N with Annual Leave")
    func testLaborCompensation2NAndLeave() {
        let params = LegalCalculatorPayloads.LaborCompensationParams(
            terminationType: .employerIllegal,
            startDate: "2020-01-01",
            endDate: "2022-06-15", // 2 years 5 months 14 days -> rounds up to 2.5 N
            averageMonthlySalary: 21750.0,
            lastMonthSalary: nil,
            unusedAnnualLeaveDays: 5.0, // 5 days unused leave
            missingInfo: nil
        )
        
        let report = LegalCalculatorEngine.calculateLaborCompensation(params: params)
        #expect(report.contains("2N"))
        #expect(report.contains("2.5 × 21750.00 × 2.0 = **108750.00** 元"))
        // Daily wage = 21750 / 21.75 = 1000
        // Annual leave pay = 5 * 1000 * 200% = 10000
        #expect(report.contains("10000.00"))
        #expect(report.contains("总计金额: 118750.00 元"))
    }
    
    @Test("Test Labor Compensation - Missing Info Prompt")
    func testLaborCompensationMissingInfo() {
        let missing = LegalCalculatorPayloads.MissingInfo(
            missingFields: ["离职日期", "离职前12个月平均工资"],
            clarificationQuestion: "请问您是哪一天正式离职的，且离职前的平均工资是多少？"
        )
        let params = LegalCalculatorPayloads.LaborCompensationParams(
            terminationType: nil,
            startDate: "2020-01-01",
            endDate: nil,
            averageMonthlySalary: nil,
            lastMonthSalary: nil,
            unusedAnnualLeaveDays: nil,
            missingInfo: missing
        )
        
        let report = LegalCalculatorEngine.calculateLaborCompensation(params: params)
        #expect(report.contains("缺少必要计算信息"))
        #expect(report.contains("请问您是哪一天正式离职的，且离职前的平均工资是多少？"))
    }
    
    @Test("Test Private Lending Interest - Standard calculation")
    func testPrivateLendingStandard() {
        let params = LegalCalculatorPayloads.PrivateLendingInterestParams(
            principal: 100000.0,
            loanStartDate: "2022-01-01",
            overdueDate: "2023-01-01", // exactly 365 days
            agreedAnnualInterestRate: 10.0, // 10%
            agreedPenaltyInterestRate: nil,
            isInterestDeductedInAdvance: false,
            missingInfo: nil
        )
        
        let report = LegalCalculatorEngine.calculatePrivateLendingInterest(params: params)
        #expect(report.contains("10000.00")) // 10% of 100k
        #expect(report.contains("本息合计总额**: **110000.00** 元"))
    }
    
    @Test("Test Private Lending Interest - Excess Rate Cutoff")
    func testPrivateLendingExcessRate() {
        // Loan after 2020, max legal is roughly 13.8%
        let params = LegalCalculatorPayloads.PrivateLendingInterestParams(
            principal: 10000.0,
            loanStartDate: "2021-01-01",
            overdueDate: "2022-01-01",
            agreedAnnualInterestRate: 36.0, // 36%, very high
            agreedPenaltyInterestRate: nil,
            isInterestDeductedInAdvance: false,
            missingInfo: nil
        )
        
        let report = LegalCalculatorEngine.calculatePrivateLendingInterest(params: params)
        #expect(report.contains("自动截断为法定最高限额"))
        #expect(report.contains("13.8"))
    }
}
