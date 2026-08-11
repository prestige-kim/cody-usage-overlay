// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodyUsageOverlay",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CodyUsageOverlay", targets: ["CodyUsageOverlay"]),
        .executable(name: "CodyUsageCoreChecks", targets: ["CodyUsageCoreChecks"]),
        .library(name: "CodyUsageCore", targets: ["CodyUsageCore"]),
    ],
    targets: [
        .target(
            name: "CodyUsageCore",
            swiftSettings: [.unsafeFlags(["-Xfrontend", "-strict-concurrency=minimal"])]
        ),
        .executableTarget(
            name: "CodyUsageOverlay",
            dependencies: ["CodyUsageCore"],
            swiftSettings: [.unsafeFlags(["-Xfrontend", "-strict-concurrency=minimal"])]
        ),
        .executableTarget(name: "CodyUsageCoreChecks", dependencies: ["CodyUsageCore"]),
    ]
)
