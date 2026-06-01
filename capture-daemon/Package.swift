// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MolyDaemon",
    platforms: [.macOS(.v13)],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MolyDaemon",
            dependencies: [],
            path: "Sources/MolyDaemon",
            swiftSettings: [.enableUpcomingFeature("BareSlashRegexLiterals")]
        ),
        .executableTarget(
            name: "AppshotNotify",
            dependencies: [],
            path: "Sources/AppshotNotify"
        ),
    ]
)
