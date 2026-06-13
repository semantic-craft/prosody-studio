import Foundation

// MARK: - 民间借贷利息分段引擎（值类型 + calculate）
//
// 时间切点：借款日 / 截止日 / 逾期起算日 / 结息转本日 / 2020-08-20(跨期强制切) / 各还款日，
// 去重升序、裁剪到 [借款日, 截止日]。逐段判 phase（借期内/逾期）、cap、利率，逐段算息（取整到分），
// 段尾先结息转本再按 5 级顺序冲抵还款（费用→借期内息→逾期息→违约金→本金）。

public struct Repayment: Sendable, Equatable {
    public let date: Date
    public let amount: Decimal
    public let note: String
    public init(date: Date, amount: Decimal, note: String = "") {
        self.date = date; self.amount = amount; self.note = note
    }
}

public struct PrivateLendingCase: Sendable {
    public var principal: Decimal            // 实际到账本金（> 0）
    public var loanDate: Date
    public var asOf: Date                     // 计算截止日（显式传入，保证确定性）
    public var contractPrincipal: Decimal?    // 合同载明本金（识别砍头息）
    public var loanEnd: Date?
    public var rate: Decimal?                 // 借期内年化利率 %（nil → 无息）
    public var overdueDate: Date?
    public var overdueRate: Decimal?          // 约定逾期年化 %
    public var penaltyRate: Decimal           // 违约金折算年化 %
    public var fees: Decimal                  // 实现债权费用
    public var repayments: [Repayment]
    public var compoundDate: Date?            // 一次性结息转本日
    public var legacyBaseRate: Decimal?       // 2015-09-01 前银行同期年利率 %
    public var professionalLender: Bool

    public init(principal: Decimal, loanDate: Date, asOf: Date,
                contractPrincipal: Decimal? = nil, loanEnd: Date? = nil,
                rate: Decimal? = nil, overdueDate: Date? = nil, overdueRate: Decimal? = nil,
                penaltyRate: Decimal = 0, fees: Decimal = 0, repayments: [Repayment] = [],
                compoundDate: Date? = nil, legacyBaseRate: Decimal? = nil,
                professionalLender: Bool = false) {
        self.principal = principal; self.loanDate = loanDate; self.asOf = asOf
        self.contractPrincipal = contractPrincipal; self.loanEnd = loanEnd
        self.rate = rate; self.overdueDate = overdueDate; self.overdueRate = overdueRate
        self.penaltyRate = penaltyRate; self.fees = fees; self.repayments = repayments
        self.compoundDate = compoundDate; self.legacyBaseRate = legacyBaseRate
        self.professionalLender = professionalLender
    }
}

public struct PrivateLendingResult: Sendable, Equatable {
    public let outstandingPrincipal: Decimal
    public let withinInterest: Decimal      // 借期内利息（未偿）
    public let overdueInterest: Decimal     // 逾期利息（未偿）
    public let penalty: Decimal             // 违约金及其他费用（未偿）
    public let fees: Decimal                // 实现债权费用（未偿）
    public let totalOutstanding: Decimal    // = 本金 + 各未偿项
    public let cumulativeWithinInterest: Decimal
    public let cumulativeOverdueInterest: Decimal
    public let cumulativePenalty: Decimal
    public let warnings: [String]
    public let assumptions: [String]
}

extension PrivateLendingInterestCalculator {

    public func calculate(_ input: PrivateLendingCase) throws -> PrivateLendingResult {
        // 校验
        guard input.principal > 0 else { throw PrivateLendingError.nonPositivePrincipal }
        if let cp = input.contractPrincipal, cp < input.principal {
            throw PrivateLendingError.contractLessThanPrincipal
        }
        guard input.asOf >= input.loanDate else { throw PrivateLendingError.asOfBeforeLoan }
        if let le = input.loanEnd, le < input.loanDate { throw PrivateLendingError.loanEndBeforeLoan }
        if let od = input.overdueDate, od < input.loanDate { throw PrivateLendingError.overdueBeforeLoan }
        for rp in input.repayments where rp.amount <= 0 { throw PrivateLendingError.invalidRepayment }

        var warnings: [String] = []
        var assumptions: [String] = []

        // 逾期起算日：未给且已过到期日 → 取到期日
        var overdueDate = input.overdueDate
        if overdueDate == nil, let le = input.loanEnd, input.asOf > le { overdueDate = le }

        if input.rate == nil { assumptions.append("未约定利率，按无息处理。") }
        if let cp = input.contractPrincipal, cp > input.principal {
            warnings.append("合同载明本金高于实际到账金额，存在砍头息迹象；利息按实际到账本金计算。")
        }
        if input.professionalLender {
            warnings.append("已标记职业放贷风险，借贷合同效力可能另需审查。")
        }

        // 状态
        var principal = input.principal
        var withinOut: Decimal = 0, withinTotal: Decimal = 0
        var overdueOut: Decimal = 0, overdueTotal: Decimal = 0
        var penaltyOut: Decimal = 0, penaltyTotal: Decimal = 0
        var feesOut = input.fees
        var capitalized = false
        var truncationWarned = false, penaltyAdjustWarned = false

        // 时间切点
        var points: Set<Date> = [input.loanDate, input.asOf]
        if let od = overdueDate, od >= input.loanDate, od <= input.asOf { points.insert(od) }
        if let cd = input.compoundDate, cd >= input.loanDate, cd <= input.asOf { points.insert(cd) }
        if input.loanDate < Self.date2020, Self.date2020 <= input.asOf { points.insert(Self.date2020) }
        for rp in input.repayments where rp.date >= input.loanDate && rp.date <= input.asOf {
            points.insert(rp.date)
        }
        let sorted = points.sorted()

        for i in 0..<max(0, sorted.count - 1) {
            let current = sorted[i], nxt = sorted[i + 1]
            let days = Self.daysBetween(current, nxt)
            if days <= 0 { continue }

            let cap = try capRate(segmentStart: current, loanDate: input.loanDate,
                                  legacyBaseRate: input.legacyBaseRate)
            let isOverdue = overdueDate.map { current >= $0 } ?? false
            var appliedRate: Decimal
            var segPenaltyRate: Decimal = 0

            if isOverdue {
                if let or = input.overdueRate {
                    appliedRate = Swift.min(or, cap)
                    if or > cap, !truncationWarned {
                        warnings.append("约定逾期利率超过法定上限，已按上限截断。"); truncationWarned = true
                    }
                } else if let r = input.rate {
                    appliedRate = Swift.min(r, cap)
                } else {
                    appliedRate = Swift.min(try defaultOverdueRate(segmentStart: current,
                                                                   legacyBaseRate: input.legacyBaseRate), cap)
                }
                segPenaltyRate = Swift.min(input.penaltyRate, Swift.max(0, cap - appliedRate))
                if input.penaltyRate > segPenaltyRate, !penaltyAdjustWarned {
                    warnings.append("违约金已调整为与逾期利息合计不超过法定上限。"); penaltyAdjustWarned = true
                }
            } else {
                let r = input.rate ?? 0
                appliedRate = Swift.min(r, cap)
                if r > cap, !truncationWarned {
                    warnings.append("约定利率超过法定上限，已按上限截断。"); truncationWarned = true
                }
            }

            let interest = annualInterest(principal: principal, annualRatePercent: appliedRate, days: days)
            let penalty = annualInterest(principal: principal, annualRatePercent: segPenaltyRate, days: days)
            if isOverdue {
                overdueOut += interest; overdueTotal += interest
                penaltyOut += penalty; penaltyTotal += penalty
            } else {
                withinOut += interest; withinTotal += interest
            }

            // 段尾：结息转本（一次性）
            if let cd = input.compoundDate, nxt == cd, !capitalized {
                if let od = overdueDate, cd >= od {
                    warnings.append("复利发生在逾期后，未滚入本金，需人工核对效力。")
                } else if withinOut > 0 {
                    principal += withinOut; withinOut = 0; capitalized = true
                    assumptions.append("按一次性结息转本处理；多次滚利需人工复核。")
                }
            }
            // 段尾：还款冲抵（费用→借期内息→逾期息→违约金→本金）
            for rp in input.repayments.filter({ $0.date == nxt }).sorted(by: { $0.amount < $1.amount }) {
                var remaining = rp.amount
                func take(_ bucket: inout Decimal) {
                    let pay = Swift.min(remaining, bucket); bucket -= pay; remaining -= pay
                }
                take(&feesOut); take(&withinOut); take(&overdueOut); take(&penaltyOut); take(&principal)
            }
        }

        let total = principal + withinOut + overdueOut + penaltyOut + feesOut
        return PrivateLendingResult(
            outstandingPrincipal: principal,
            withinInterest: withinOut, overdueInterest: overdueOut,
            penalty: penaltyOut, fees: feesOut, totalOutstanding: total,
            cumulativeWithinInterest: withinTotal, cumulativeOverdueInterest: overdueTotal,
            cumulativePenalty: penaltyTotal,
            warnings: orderedUnique(warnings), assumptions: orderedUnique(assumptions))
    }
}

/// 去重并保序。
private func orderedUnique(_ items: [String]) -> [String] {
    var seen = Set<String>(); var out: [String] = []
    for x in items where seen.insert(x).inserted { out.append(x) }
    return out
}
