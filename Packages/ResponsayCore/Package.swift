// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ResponsayCore",
    platforms: [.macOS(.v14), .iOS(.v18)],
    products: [
        .library(name: "ResponsayCore", targets: ["ResponsayCore"]),
        // 354 — shared speech package: capture-service implementations + (later) the
        // on-device engine, reusable by both the macOS and iOS app targets.
        .library(name: "ResponsaySpeech", targets: ["ResponsaySpeech"])
    ],
    targets: [
        .target(
            name: "ResponsayCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(
            name: "ResponsaySpeech",
            dependencies: ["ResponsayCore"]
        ),
        .testTarget(name: "ResponsayCoreTests", dependencies: ["ResponsayCore"])
    ]
)
