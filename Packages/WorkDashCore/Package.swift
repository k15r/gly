// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "WorkDashCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WorkDashCore", targets: ["WorkDashCore"]),
        .library(name: "WorkDashMCP", targets: ["WorkDashMCP"]),
        .library(name: "WorkDashEditor", targets: ["WorkDashEditor"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.9.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
    ],
    targets: [
        .target(
            name: "WorkDashCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .target(
            name: "WorkDashMCP",
            dependencies: ["WorkDashCore", .product(name: "MCP", package: "swift-sdk")]
        ),
        .target(
            name: "WorkDashEditor",
            dependencies: ["WorkDashCore"]
        ),
        .testTarget(
            name: "WorkDashEditorTests",
            dependencies: ["WorkDashEditor", "WorkDashCore"]
        ),
        .testTarget(
            name: "WorkDashCoreTests",
            dependencies: ["WorkDashCore"]
        ),
        .testTarget(
            name: "WorkDashMCPTests",
            dependencies: ["WorkDashMCP", .product(name: "MCP", package: "swift-sdk")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
