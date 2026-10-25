// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "eventkit-probe",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "eventkit-probe",
            path: "Sources",
            linkerSettings: [
                // Embed Info.plist so TCC shows the calendar usage description for this CLI tool.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Info.plist",
                ]),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
