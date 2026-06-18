// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "symaira-tune",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "SymTuneCore", targets: ["SymTuneCore"]),
        .library(name: "SymTuneMCP", targets: ["SymTuneMCP"]),
        .executable(name: "symtune", targets: ["symtune"]),
    ],
    targets: [
        .target(
            name: "SymTuneCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
            ]
        ),
        .target(
            name: "SymTuneMCP",
            dependencies: ["SymTuneCore"]
        ),
        .executableTarget(
            name: "symtune",
            dependencies: ["SymTuneCore", "SymTuneMCP"]
        ),
        .testTarget(
            name: "SymTuneCoreTests",
            dependencies: ["SymTuneCore"]
        ),
    ],
    // v0.1 ships in Swift 5 language mode. Tightening to Swift 6 strict
    // concurrency (AppKit MainActor isolation in DisplayService et al.) is a
    // tracked roadmap item — see docs/roadmap.md.
    swiftLanguageModes: [.v5]
)
