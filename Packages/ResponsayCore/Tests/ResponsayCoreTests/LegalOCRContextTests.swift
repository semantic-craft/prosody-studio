import Testing
@testable import ResponsayCore

/// 111 — explicit OCR-assisted legal context: offer policy + payload bridge + privacy.
struct LegalOCRContextTests {
    private let privacy = LegalPrivacyPolicy()

    // MARK: - Offer policy (never automatic)

    @Test func offersOCR_onlyWhenAXYieldsNoText() {
        #expect(LegalOCRContext.shouldOfferOCR(axText: nil) == true)
        #expect(LegalOCRContext.shouldOfferOCR(axText: "   \n ") == true)
        #expect(LegalOCRContext.shouldOfferOCR(axText: "被告应承担违约责任") == false)
    }

    // MARK: - Payload bridge (reuses the built type; source = .ocr)

    @Test func payload_labelsSourceOCR_noFork() {
        let payload = LegalOCRContext.payload(
            fromOCRText: "  本案标的额 120 万元。 ", scene: .litigation, stage: .evidenceReview,
            appName: "Electron")
        #expect(payload?.source == .ocr)
        #expect(payload?.contextScope == .selectedTextOnly)
        #expect(payload?.selectedText == "本案标的额 120 万元。")   // trimmed
        #expect(payload?.scene == .litigation)
    }

    @Test func payload_nilForEmptyOCR() {
        #expect(LegalOCRContext.payload(fromOCRText: "   ", scene: .privacy, stage: .piaTriage, appName: "x") == nil)
    }

    // MARK: - 110 privacy: OCR is sensitive → never auto-sends

    @Test func ocrSource_neverAutoSendsToCloud_evenCloudFirst() {
        let d = privacy.decide(gate: .allowed, selectedText: "普通文本", source: .ocr, modelPreference: .cloudFirst)
        #expect(d.route == .cloudRequiresUserConfirm)         // not .cloudAllowed
        #expect(d.reasons.contains { $0.contains("OCR") })
    }

    @Test func ocrSource_localFirst_staysLocal() {
        let d = privacy.decide(gate: .allowed, selectedText: "普通文本", source: .ocr, modelPreference: .localFirst)
        #expect(d.route == .localOnly)
    }

    @Test func accessibilitySource_unchangedRegression() {
        // The added source param must not change the default (.accessibility) behavior.
        let d = privacy.decide(gate: .allowed, selectedText: "普通文本", modelPreference: .cloudFirst)
        #expect(d.route == .cloudAllowed)
    }

    @Test func ocrSecureField_stillBlocked() {
        let d = privacy.decide(gate: .denied(.secureTextField), selectedText: "x", source: .ocr)
        #expect(d.route == .blocked)   // the gate still wins over OCR routing
    }
}
