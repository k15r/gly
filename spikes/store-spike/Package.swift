// swift-tools-version:6.0
// Spike 2 (foundation-spikes): GRDB/SQLite store. Throwaway code.
import PackageDescription

let package = Package(
    name: "store-spike",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "StoreSpike", targets: ["StoreSpike"]),   // reused by the mcp-spike agent (task 4.5)
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.9.0"),
    ],
    targets: [
        .target(
            name: "StoreSpike",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .executableTarget(
            name: "StoreSpikeUI",
            dependencies: ["StoreSpike", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(
            name: "StoreSpikeTests",
            dependencies: ["StoreSpike"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
