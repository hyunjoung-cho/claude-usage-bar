// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ClaudeUsageBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClaudeUsageBar", targets: ["ClaudeUsageBarApp"])
    ],
    targets: [
        .target(
            name: "ClaudeUsageBarCore",
            path: "Sources/ClaudeUsageBarCore"
        ),
        .executableTarget(
            name: "ClaudeUsageBarApp",
            dependencies: ["ClaudeUsageBarCore"],
            path: "Sources/ClaudeUsageBarApp",
            resources: [.copy("Resources/default-sets")]
        ),
        .executableTarget(
            name: "CoreTestRunner",
            dependencies: ["ClaudeUsageBarCore"],
            path: "Sources/CoreTestRunner"
        )
    ]
)
