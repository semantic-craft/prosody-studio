import Testing
@testable import ResponsayCore

/// 110 — LegalPrivacyPolicy: gate-first block + sensitivity routing + send-preview.
struct LegalPrivacyPolicyTests {
    private let policy = LegalPrivacyPolicy()
    private let provider = ModelProviderRouter()

    // MARK: - AC1: secure field blocks the legal path

    @Test func secureField_blocksLegalPath() {
        let d = policy.decide(gate: .denied(.secureTextField), selectedText: "任意文本")
        #expect(d.route == .blocked)
        #expect(d.isBlocked)
        #expect(d.sendFields.isEmpty)               // nothing is read or sent
        #expect(d.reasons.first?.contains("已阻止") == true)
    }

    @Test func compatibilityDenial_doesNotBlockLegalPath() {
        // Only the SECURITY axis blocks; an injection-compat denial is irrelevant to privacy.
        let d = policy.decide(
            gate: .denied(.incompatibleApp(bundleID: "com.microsoft.Excel")),
            selectedText: "普通文本", modelPreference: .cloudFirst)
        #expect(d.route != .blocked)
    }

    // MARK: - AC2: sensitive content never auto-sends to cloud

    @Test func sensitiveTerm_requiresConfirmEvenWhenCloudFirst() {
        let d = policy.decide(gate: .allowed, selectedText: "涉及客户保密信息", modelPreference: .cloudFirst)
        #expect(d.route == .cloudRequiresUserConfirm)
        #expect(d.requiresUserConfirm)
        #expect(d.reasons.contains { $0.contains("敏感词") })
    }

    @Test func sensitiveApp_feishu_requiresConfirm() {
        let d = policy.decide(gate: .allowed, selectedText: "上线评审材料", appName: "Feishu", modelPreference: .cloudFirst)
        #expect(d.route == .cloudRequiresUserConfirm)
        #expect(d.reasons.contains { $0.contains("企业协作") })
    }

    @Test func surroundingTextDrivesSensitivity_butIsNeverSent() {
        let d = policy.decide(
            gate: .allowed, selectedText: "见附件", surroundingText: "客户保密资料清单",
            modelPreference: .cloudFirst)
        #expect(d.route == .cloudRequiresUserConfirm)              // surrounding triggered it
        #expect(d.sendFields == [.selectedText, .sceneTag, .appCategory])   // surrounding NOT a field
    }

    @Test func nonSensitive_cloudFirst_allowsCloud() {
        let d = policy.decide(gate: .allowed, selectedText: "这段话需要改写一下", modelPreference: .cloudFirst)
        #expect(d.route == .cloudAllowed)
    }

    @Test func localFirst_alwaysLocal() {
        let d = policy.decide(gate: .allowed, selectedText: "普通文本", modelPreference: .localFirst)
        #expect(d.route == .localOnly)
    }

    @Test func askEachTime_alwaysConfirms() {
        let d = policy.decide(gate: .allowed, selectedText: "普通文本", modelPreference: .askEachTime)
        #expect(d.route == .cloudRequiresUserConfirm)
    }

    // MARK: - AC3: send-preview = minimal default fields

    @Test func sendPreview_defaultsToMinimalFields() {
        let d = policy.decide(gate: .allowed, selectedText: "x", privacyPreference: .selectedTextOnly)
        #expect(d.sendFields.contains(.selectedText))
        #expect(d.sendFields.contains(.sceneTag))
        #expect(d.sendFields.contains(.windowTitleHash) == false)   // withheld by default
        #expect(d.sendFields.contains(.nearbyHeading) == false)
    }

    @Test func relaxedScope_addsNearbyHeadingOnly() {
        let d = policy.decide(gate: .allowed, selectedText: "x", privacyPreference: .allowLocalHeading)
        #expect(d.sendFields.contains(.nearbyHeading))
        #expect(d.sendFields.contains(.windowTitleHash) == false)
    }

    // MARK: - v0.2 §14: privacy axis composes with the purpose router

    @Test func composesWithProviderRouter_localNeverUpgraded() {
        let d = policy.decide(gate: .allowed, selectedText: "x", modelPreference: .localFirst)
        let effective = provider.route(purpose: .legalSkill, baseRoute: d.route)
        #expect(effective == .localOnly)
        #expect(provider.allowsCloud(effective) == false)
    }
}
