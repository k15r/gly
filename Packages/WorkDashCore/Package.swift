// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "WorkDashCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WorkDashCore", targets: ["WorkDashCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.9.0"),
    ],
    targets: [
        .target(
            name: "WorkDashCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(
            name: "WorkDashCoreTests",
            dependencies: ["WorkDashCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
