// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "UsageKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(name: "UsageKit", targets: ["UsageKit"]),
    ],
    targets: [
        .target(
            name: "UsageKit",
            exclude: ["Providers/Claude/CLAUDE.md", "Providers/Codex/CLAUDE.md"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "UsageKitTests",
            dependencies: ["UsageKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
