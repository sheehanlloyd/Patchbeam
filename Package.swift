// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Patchbeam",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PatchbeamCore", targets: ["PatchbeamCore"]),
        .executable(name: "Patchbeam", targets: ["PatchbeamApp"]),
        .executable(name: "patchbeam-cli", targets: ["PatchbeamCLI"]),
    ],
    targets: [
        // All domain logic. No SwiftUI/AppKit imports so it is testable headless.
        .target(
            name: "PatchbeamCore",
            path: "Sources/PatchbeamCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        // Native SwiftUI + AppKit notch app.
        .executableTarget(
            name: "PatchbeamApp",
            dependencies: ["PatchbeamCore"],
            path: "Sources/PatchbeamApp"
        ),
        // Headless driver used by scripts/fixture-demo.sh and CI.
        .executableTarget(
            name: "PatchbeamCLI",
            dependencies: ["PatchbeamCore"],
            path: "Sources/PatchbeamCLI"
        ),
        .testTarget(
            name: "PatchbeamCoreTests",
            dependencies: ["PatchbeamCore"],
            path: "Tests/PatchbeamCoreTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
