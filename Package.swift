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
        .testTarget(
            name: "SymTuneMCPTests",
            dependencies: ["SymTuneMCP"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
