// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "GlyCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GlyCore", targets: ["GlyCore"]),
        .library(name: "GlyMCP", targets: ["GlyMCP"]),
        .library(name: "GlyEditor", targets: ["GlyEditor"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.9.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
        // Lint on build (warnings in Xcode); config in .swiftlint.yml.
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.65.1"),
    ],
    targets: [
        .target(
            name: "GlyCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")]
        ),
        .target(
            name: "GlyMCP",
            dependencies: ["GlyCore", .product(name: "MCP", package: "swift-sdk")],
            plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")]
        ),
        .target(
            name: "GlyEditor",
            dependencies: ["GlyCore"],
            plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")]
        ),
        .testTarget(
            name: "GlyEditorTests",
            dependencies: ["GlyEditor", "GlyCore"]
        ),
        .testTarget(
            name: "GlyCoreTests",
            dependencies: ["GlyCore"]
        ),
        .testTarget(
            name: "GlyMCPTests",
            dependencies: ["GlyMCP", .product(name: "MCP", package: "swift-sdk")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
