import Foundation

/// Defines the JSON Schemas that the LLM is expected to output when executing a Legal Calculator skill.
public enum LegalCalculatorPayloads {
    
    // MARK: - Labor Fee Payloads
    
    /// The standardized payload for labor fee extraction.
    public struct LaborCompensationParams: Codable, Equatable, Sendable {
        /// Type of termination: e.g., "employer_illegal" (2N), "employer_legal_no_notice" (N+1), "employer_legal_with_notice" (N), "employee_resign" (0), "mutual_agreement" (N).
        public let terminationType: TerminationType?
        
        /// Employment start date in ISO8601 (YYYY-MM-DD).
        public let startDate: String?
        
        /// Employment end date in ISO8601 (YYYY-MM-DD).
        public let endDate: String?
        
        /// Average monthly salary over the last 12 months (or employment period if less than 12 months).
        public let averageMonthlySalary: Double?
        
        /// Base salary for calculating N+1 (if different from average, typically just the last month's salary).
        public let lastMonthSalary: Double?
        
        /// Accrued but unused annual leave days.
        public let unusedAnnualLeaveDays: Double?
        
        /// Specific missing information that needs to be asked to the user.
        public let missingInfo: MissingInfo?
        
        public enum TerminationType: String, Codable, Sendable {
            case employerIllegal = "employer_illegal"
            case employerLegalNoNotice = "employer_legal_no_notice"
            case employerLegalWithNotice = "employer_legal_with_notice"
            case mutualAgreement = "mutual_agreement"
            case employeeResign = "employee_resign"
            case unknown = "unknown"
        }
        
        public init(
            terminationType: TerminationType?,
            startDate: String?,
            endDate: String?,
            averageMonthlySalary: Double?,
            lastMonthSalary: Double?,
            unusedAnnualLeaveDays: Double?,
            missingInfo: MissingInfo? = nil
        ) {
            self.terminationType = terminationType
            self.startDate = startDate
            self.endDate = endDate
            self.averageMonthlySalary = averageMonthlySalary
            self.lastMonthSalary = lastMonthSalary
            self.unusedAnnualLeaveDays = unusedAnnualLeaveDays
            self.missingInfo = missingInfo
        }
    }
    
    // MARK: - Private Lending Interest Payloads
    
    /// The standardized payload for private lending interest extraction.
    public struct PrivateLendingInterestParams: Codable, Equatable, Sendable {
        /// Principal amount (in RMB).
        public let principal: Double?
        
        /// Start date of the loan in ISO8601 (YYYY-MM-DD).
        public let loanStartDate: String?
        
        /// Overdue date (default date of default) in ISO8601 (YYYY-MM-DD).
        public let overdueDate: String?
        
        /// Agreed annual interest rate percentage (e.g., 24.0 for 24%).
        public let agreedAnnualInterestRate: Double?
        
        /// Agreed penalty interest rate percentage (e.g., 10.0 for 10%).
        public let agreedPenaltyInterestRate: Double?
        
        /// Has the interest been deducted from the principal in advance? (头息)
        public let isInterestDeductedInAdvance: Bool?
        
        /// Specific missing information that needs to be asked to the user.
        public let missingInfo: MissingInfo?
        
        public init(
            principal: Double?,
            loanStartDate: String?,
            overdueDate: String?,
            agreedAnnualInterestRate: Double?,
            agreedPenaltyInterestRate: Double?,
            isInterestDeductedInAdvance: Bool?,
            missingInfo: MissingInfo? = nil
        ) {
            self.principal = principal
            self.loanStartDate = loanStartDate
            self.overdueDate = overdueDate
            self.agreedAnnualInterestRate = agreedAnnualInterestRate
            self.agreedPenaltyInterestRate = agreedPenaltyInterestRate
            self.isInterestDeductedInAdvance = isInterestDeductedInAdvance
            self.missingInfo = missingInfo
        }
    }
    
    // MARK: - Fact Check Verification Payloads
    
    /// The standardized payload for Fact Check extraction (deep link mode).
    public struct VerificationFactCheckPayload: Codable, Equatable, Sendable {
        
        public enum TargetType: String, Codable, Sendable {
            case law
            case caseLaw = "case"
            case paper
        }
        
        public struct VerificationTarget: Codable, Equatable, Sendable {
            /// "law" or "case"
            public let type: TargetType
            
            /// For law: statute name & article number (e.g. "民法典 第一千零二十四条").
            /// For case: exact case number (e.g. "(2021)最高法民再1号").
            public let keywords: String?
            
            /// For case/law where keywords are unknown, a chunk of facts (100-800 words).
            public let semanticText: String?
            
            /// The original sentence from the user's text that triggered this verification.
            public let originalText: String
            
            public init(type: TargetType, keywords: String?, semanticText: String?, originalText: String) {
                self.type = type
                self.keywords = keywords
                self.semanticText = semanticText
                self.originalText = originalText
            }
        }
        
        public let targets: [VerificationTarget]
        
        public init(targets: [VerificationTarget]) {
            self.targets = targets
        }
    }
    
    // MARK: - Shared
    
    public struct MissingInfo: Codable, Equatable, Sendable {
        /// A list of field descriptions that are missing (e.g., "入职日期", "离职前12个月平均工资").
        public let missingFields: [String]
        
        /// A direct, natural language question to ask the user to provide this information.
        public let clarificationQuestion: String
        
        public init(missingFields: [String], clarificationQuestion: String) {
            self.missingFields = missingFields
            self.clarificationQuestion = clarificationQuestion
        }
    }
}
