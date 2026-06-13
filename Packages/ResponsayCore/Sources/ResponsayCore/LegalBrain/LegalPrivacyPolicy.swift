import Foundation

// MARK: - 110 LegalPrivacyPolicy + ModelRoute + send-preview
//
// The confidentiality differentiator. Runs AFTER the capture gate (052/080) and
// never bypasses it: a security denial → `.blocked`. Then it decides the model
// route from sensitivity + the user's preference, and lists EXACTLY which fields a
// cloud call may send (never the whole document). Deterministic / Foundation-only;
// it is the privacy axis the `ModelProviderRouter` (106) consults (v0.2 §14).

/// A field that may be sent to a cloud model. The send-preview shows exactly these.
public enum LegalSendField: String, Sendable, Equatable, CaseIterable {
    case selectedText      // 选中文本
    case sceneTag          // 场景标签（litigation/privacy…）
    case appCategory       // 应用类别（如 wordProcessor）— coarse, non-identifying
    case nearbyHeading     // 附近标题（仅在用户放宽时）
    case windowTitleHash   // 窗口标题哈希（v0 默认不发送）

    public var label: String {
        switch self {
        case .selectedText:    return "选中文本"
        case .sceneTag:        return "场景标签"
        case .appCategory:     return "应用类别"
        case .nearbyHeading:   return "附近标题"
        case .windowTitleHash: return "窗口标题（哈希）"
        }
    }
}

public struct LegalPrivacyDecision: Sendable, Equatable {
    public let route: ModelRoute
    /// Exactly the fields a cloud call may send (the send-preview). Empty when blocked.
    public let sendFields: [LegalSendField]
    public let reasons: [String]

    public init(route: ModelRoute, sendFields: [LegalSendField], reasons: [String]) {
        self.route = route
        self.sendFields = sendFields
        self.reasons = reasons
    }

    public var isBlocked: Bool { route == .blocked }
    public var requiresUserConfirm: Bool { route == .cloudRequiresUserConfirm }
    public var allowsCloud: Bool { route == .cloudAllowed || route == .cloudRequiresUserConfirm }
}

public struct LegalPrivacyPolicy: Sendable {
    public init() {}

    /// Decide route + send-preview. `surroundingText` is used for the LOCAL sensitivity
    /// check only — it is NEVER added to `sendFields`.
    public func decide(
        gate: CaptureGateDecision,
        selectedText: String,
        surroundingText: String? = nil,
        appName: String? = nil,
        source: LegalContextSource = .accessibility,
        privacyPreference: PrivacyPreference = .selectedTextOnly,
        modelPreference: ModelPreference = .askEachTime
    ) -> LegalPrivacyDecision {
        // 1. The capture gate is law: a SECURITY denial blocks the legal path entirely.
        if gate.denyAxis == .security {
            return LegalPrivacyDecision(
                route: .blocked, sendFields: [],
                reasons: ["安全输入框 / 敏感应用：法律路径已阻止（不读取、不发送）。"])
        }

        // 2. Sensitivity (local-only signal: selected + surrounding + app + OCR source).
        var reasons: [String] = []
        let haystack = [selectedText, surroundingText ?? ""].joined(separator: "\n")
        let hitTerm = Self.sensitiveTerms.first { haystack.contains($0) }
        let sensitiveApp = appName.map { name in
            Self.sensitiveAppFragments.contains { name.lowercased().contains($0) }
        } ?? false
        // OCR-derived text (111) is treated as sensitive client material → never auto-send.
        let isOCR = source == .ocr
        if let hitTerm { reasons.append("检测到敏感词「\(hitTerm)」，默认不自动发送云端。") }
        if sensitiveApp { reasons.append("企业协作应用：默认不自动发送云端。") }
        if isOCR { reasons.append("OCR 取文：可能含敏感文档内容，默认本地优先 / 发送前确认。") }
        let sensitive = hitTerm != nil || sensitiveApp || isOCR

        // 3. Route ladder. localFirst always wins; sensitive never auto-sends.
        let route: ModelRoute
        switch modelPreference {
        case .localFirst:
            route = .localOnly
            reasons.append("本地优先：仅本地模型。")
        case .cloudFirst:
            route = sensitive ? .cloudRequiresUserConfirm : .cloudAllowed
        case .askEachTime:
            route = .cloudRequiresUserConfirm
            if !sensitive { reasons.append("每次询问：发送云端前需确认。") }
        }

        // 4. Send-preview: the minimal default set (v0.2 §14: selectedText + sceneTag +
        //    appCategory). windowTitle/full-URL withheld by default; nearbyHeading only
        //    when the user relaxes scope. Surrounding text is never sent.
        var sendFields: [LegalSendField] = [.selectedText, .sceneTag, .appCategory]
        if privacyPreference != .selectedTextOnly { sendFields.append(.nearbyHeading) }

        return LegalPrivacyDecision(route: route, sendFields: sendFields, reasons: reasons)
    }

    // MARK: - Dictionaries (small, deterministic; extendable via resource later)

    static let sensitiveTerms: [String] = [
        "保密", "客户", "仲裁", "未公开", "身份证", "银行账号", "银行卡", "商业秘密", "机密", "病历",
    ]

    static let sensitiveAppFragments: [String] = ["feishu", "飞书", "lark"]
}
