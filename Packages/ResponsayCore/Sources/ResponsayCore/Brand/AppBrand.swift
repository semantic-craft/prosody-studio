import Foundation

public enum AppBrand {
    public static let displayName = "Responsay"
    public static let appSupportDirectoryName = "Responsay"
    public static let urlScheme = "responsay"
    public static let backendClientID = "responsay-mac"
    public static let loggerSubsystem = "com.semanticcraft.responsay.mac"
    public static let userAgent = "Responsay/0.1"

    public static let iOSBundleIdentifier = "com.semanticcraft.responsay"
    public static let macOSBundleIdentifier = "com.semanticcraft.responsay.mac"

    // Legacy names are only for local cleanup scripts, rename inventory, and tests.
    public static let legacyDisplayName = "Cadenta"
    public static let legacyIOSBundleIdentifier = "com.semanticcraft.cadenta"
    public static let legacyMacOSBundleIdentifier = "com.semanticcraft.cadenta.mac"
}
