// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DynamicMainland",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CDynamicMainland",
            path: "Sources/CDynamicMainland",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "DynamicMainland",
            dependencies: ["CDynamicMainland"],
            path: "Sources/DynamicMainland",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L", "target/release",
                ]),
                .linkedLibrary("dynamic_mainland_core"),
            ]
        ),
    ]
)
