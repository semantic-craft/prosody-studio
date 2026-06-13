import Foundation

/// Core engine for executing legal calculations in Swift.
public struct LegalCalculatorEngine {
    
    // MARK: - Labor Compensation Calculation
    
    /// Calculates the labor severance fee and returns a detailed markdown report.
    ///
    /// The formula for severance pay (N) is:
    /// N = years of service * average monthly salary over the last 12 months.
    /// - If service period < 6 months, N = 0.5
    /// - If service period >= 6 months and < 1 year, N = 1.0
    ///
    /// - Parameters:
    ///   - params: The payload extracted by the LLM.
    /// - Returns: A markdown formatted string containing the calculation details, or an error/missing info prompt.
    public static func calculateLaborCompensation(params: LegalCalculatorPayloads.LaborCompensationParams) -> String {
        // 1. Check for missing information
        if let missing = params.missingInfo {
            return "### ⚠️ 缺少必要计算信息\n\n为了能够进行准确的费用计算，我还需要了解以下信息：\n- " + missing.missingFields.joined(separator: "\n- ") + "\n\n**\(missing.clarificationQuestion)**"
        }
        
        // 2. Validate essential fields
        guard let startDateStr = params.startDate, let endDateStr = params.endDate,
              let avgSalary = params.averageMonthlySalary, let type = params.terminationType else {
            return "### ❌ 计算失败\n\n提取的参数不完整，无法进行计算。请提供完整的入职日期、离职日期和平均工资。"
        }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        
        guard let startDate = formatter.date(from: startDateStr),
              let endDate = formatter.date(from: endDateStr),
              endDate > startDate else {
            return "### ❌ 计算失败\n\n入职日期和离职日期格式有误或离职日期早于入职日期。"
        }
        
        // 3. Calculate years of service (N)
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: startDate, to: endDate)
        
        let years = components.year ?? 0
        let months = components.month ?? 0
        let days = components.day ?? 0
        
        var n: Double = Double(years)
        if months >= 6 {
            n += 1.0
        } else if months > 0 || days > 0 {
            n += 0.5
        }
        
        if n == 0 {
            n = 0.5 // Minimum is 0.5
        }
        
        // 4. Determine compensation multiplier based on termination type
        var multiplier = 0.0
        var typeDescription = ""
        
        switch type {
        case .employerIllegal:
            multiplier = 2.0 // 2N (赔偿金)
            typeDescription = "违法解除劳动合同 (2N赔偿金)"
        case .employerLegalNoNotice:
            multiplier = 1.0 // N + 1 (代通知金)
            typeDescription = "合法解除未提前30天通知 (N+1, 代通知金为1个月工资)"
        case .employerLegalWithNotice, .mutualAgreement:
            multiplier = 1.0 // N (经济补偿金)
            typeDescription = "合法解除或协商一致 (N经济补偿金)"
        case .employeeResign:
            multiplier = 0.0
            typeDescription = "劳动者主动辞职 (无经济补偿)"
        case .unknown:
            return "### ⚠️ 离职性质不明\n\n无法确定离职的性质（违法解除、合法解除等），请补充。"
        }
        
        // 5. Calculate base compensation
        let baseCompensation = n * avgSalary * multiplier
        
        // N+1 additional 1 month
        var noticePay = 0.0
        if type == .employerLegalNoNotice {
            let lastSalary = params.lastMonthSalary ?? avgSalary
            noticePay = lastSalary
        }
        
        let totalSeverance = baseCompensation + noticePay
        
        // 6. Calculate unused annual leave (200% of daily wage)
        // Daily wage = monthly / 21.75
        let dailyWage = avgSalary / 21.75
        var annualLeavePay = 0.0
        var annualLeaveDetails = ""
        
        if let leaveDays = params.unusedAnnualLeaveDays, leaveDays > 0 {
            // Statutory calculation: 200% of daily wage for unused days (since normal 100% is already paid in normal salary)
            annualLeavePay = leaveDays * dailyWage * 2.0
            annualLeaveDetails = """
            - **未休年假工资**: \(leaveDays)天 × (\(String(format: "%.2f", avgSalary)) ÷ 21.75) × 200% = **\(String(format: "%.2f", annualLeavePay))** 元
            """
        }
        
        let grandTotal = totalSeverance + annualLeavePay
        
        // 7. Format report
        var report = """
        ### 💰 劳动费用计算明细
        
        **基本信息:**
        - **工作区间**: \(startDateStr) 至 \(endDateStr)
        - **离职前12月平均工资**: \(String(format: "%.2f", avgSalary)) 元
        - **工作年限 (N)**: \(n) (具体为 \(years)年 \(months)个月 \(days)天)
        - **离职性质**: \(typeDescription)
        
        **计算明细:**
        - **经济补偿/赔偿金 (\(multiplier == 2.0 ? "2N" : "N"))**: \(n) × \(String(format: "%.2f", avgSalary)) × \(multiplier) = **\(String(format: "%.2f", baseCompensation))** 元
        """
        
        if noticePay > 0 {
            report += "\n- **代通知金 (+1)**: **\(String(format: "%.2f", noticePay))** 元"
        }
        
        if !annualLeaveDetails.isEmpty {
            report += "\n" + annualLeaveDetails
        }
        
        report += "\n\n**总计金额: \(String(format: "%.2f", grandTotal)) 元**"
        report += "\n\n> *注：此计算未包含社保公积金补缴、加班费基准等复杂情况，且最高补偿基数（当地社平工资3倍）需要结合实际归属地判断，本结果仅供参考。*"
        
        return report
    }
    
    // MARK: - Private Lending Interest Calculation
    
    /// Calculates the interest and principal for private lending based on the LPR caps.
    ///
    /// - Parameters:
    ///   - params: The payload extracted by the LLM.
    /// - Returns: A markdown formatted string containing the calculation details.
    public static func calculatePrivateLendingInterest(params: LegalCalculatorPayloads.PrivateLendingInterestParams) -> String {
        // 1. Check for missing information
        if let missing = params.missingInfo {
            return "### ⚠️ 缺少必要计算信息\n\n为了能够进行准确的利息计算，我还需要了解以下信息：\n- " + missing.missingFields.joined(separator: "\n- ") + "\n\n**\(missing.clarificationQuestion)**"
        }
        
        // 2. Validate essential fields
        guard let principal = params.principal, let startDateStr = params.loanStartDate else {
            return "### ❌ 计算失败\n\n提取的参数不完整，无法进行计算。请提供借款本金和借款日期。"
        }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        
        guard let startDate = formatter.date(from: startDateStr) else {
            return "### ❌ 计算失败\n\n借款日期格式有误。"
        }
        
        let endDate: Date
        if let overdueStr = params.overdueDate, let parsedOverdue = formatter.date(from: overdueStr) {
            endDate = parsedOverdue
        } else {
            endDate = Date() // defaults to today if not provided
        }
        
        if endDate <= startDate {
            return "### ❌ 计算失败\n\n截止日期早于或等于借款日期。"
        }
        
        // 3. Determine actual principal (deducting advance interest)
        var actualPrincipal = principal
        if params.isInterestDeductedInAdvance == true {
            actualPrincipal = principal * 0.9 // Simple placeholder logic for '头息', normally we'd need the exact amount deducted
        }
        
        // 4. LPR Segment Calculation (Simplified for demo, standard logic has pre-2020 24%/36% and post-2020 4x LPR)
        let isPost2020 = startDate >= (formatter.date(from: "2020-08-20") ?? Date())
        let maxLegalInterestRate = isPost2020 ? 13.8 : 24.0 // simplified 4x LPR as 13.8%
        
        // Determine the rate to apply
        var appliedRate = params.agreedAnnualInterestRate ?? 0.0
        var rateDescription = "双方约定的年利率 (\(appliedRate)%)"
        
        if appliedRate > maxLegalInterestRate {
            appliedRate = maxLegalInterestRate
            rateDescription = "约定的利率过高，自动截断为法定最高限额 (\(maxLegalInterestRate)%)"
        } else if appliedRate == 0.0 {
            rateDescription = "未约定利息，按法定默认规则（暂不支持无约定的逾期利息精密计算）"
        }
        
        // 5. Calculate Days and Interest
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        let years = Double(days) / 365.0
        
        let totalInterest = actualPrincipal * (appliedRate / 100.0) * years
        let grandTotal = actualPrincipal + totalInterest
        
        // 6. Format report
        let report = """
        ### 💰 民间借贷本息计算明细
        
        **基本信息:**
        - **借款区间**: \(startDateStr) 至 \(formatter.string(from: endDate)) (共 \(days) 天)
        - **票面本金**: \(String(format: "%.2f", principal)) 元
        - **实际出借本金**: \(String(format: "%.2f", actualPrincipal)) 元 \(params.isInterestDeductedInAdvance == true ? "(已扣除预先支付的利息/头息)" : "")
        - **适用年利率**: \(rateDescription)
        
        **计算明细:**
        - **利息**: \(String(format: "%.2f", actualPrincipal)) × \(appliedRate)% × \(String(format: "%.4f", years))年 = **\(String(format: "%.2f", totalInterest))** 元
        - **本息合计总额**: **\(String(format: "%.2f", grandTotal))** 元
        
        > *注：民间借贷涉及《民法典》及2020年最高法司法解释规定的新旧法衔接，2020年8月20日前后受不同利率上限（24%与4倍LPR）约束，此计算结果仅为预估，实际金额以法院裁判为准。*
        """
        
        return report
    }
}
