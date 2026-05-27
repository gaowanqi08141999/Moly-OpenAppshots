// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QClawDaemon",
    platforms: [.macOS(.v13)],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "QClawDaemon",
            dependencies: [],
            path: "Sources/QClawDaemon",
            swiftSettings: [.enableUpcomingFeature("BareSlashRegexLiterals")]
        ),
    ]
)
