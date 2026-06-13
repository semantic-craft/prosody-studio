import Testing
@testable import ResponsayCore

@Test func appBrand_usesResponsayIdentity() {
    #expect(AppBrand.displayName == "Responsay")
    #expect(AppBrand.appSupportDirectoryName == "Responsay")
    #expect(AppBrand.urlScheme == "responsay")
    #expect(AppBrand.backendClientID == "responsay-mac")
    #expect(AppBrand.iOSBundleIdentifier == "com.semanticcraft.responsay")
    #expect(AppBrand.macOSBundleIdentifier == "com.semanticcraft.responsay.mac")
}

@Test func appBrand_keepsLegacyIdentityOnlyForCleanupBoundaries() {
    #expect(AppBrand.legacyDisplayName == "Cadenta")
    #expect(AppBrand.legacyIOSBundleIdentifier == "com.semanticcraft.cadenta")
    #expect(AppBrand.legacyMacOSBundleIdentifier == "com.semanticcraft.cadenta.mac")
}
