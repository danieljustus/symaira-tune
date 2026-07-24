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
        .executable(name: "SymTuneApp", targets: ["SymTuneApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/danieljustus/symaira-appkit.git", revision: "019e506"),
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
            dependencies: [
                "SymTuneCore",
                "SymTuneMCP",
                .product(name: "SymairaUpdateCheck", package: "symaira-appkit"),
            ]
        ),
        .executableTarget(
            name: "SymTuneApp",
            dependencies: [
                "SymTuneCore",
                .product(name: "SymairaUpdateCheck", package: "symaira-appkit"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
            ]
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
