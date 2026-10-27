// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BudsBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "BudsBar", targets: ["BudsBar"]),
        .library(name: "BudsCore", targets: ["BudsCore"]),
        .library(name: "BudsUI", targets: ["BudsUI"]),
    ],
    targets: [
        .target(
            name: "BudsCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "BudsUI",
            dependencies: ["BudsCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "BudsBar",
            dependencies: ["BudsCore", "BudsUI"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Headless diagnostic that exercises the same protocol code the app uses.
        .executableTarget(
            name: "BudsProbe",
            dependencies: ["BudsCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Renders the control panel to PNG for documentation and review.
        .executableTarget(
            name: "BudsPanelShot",
            dependencies: ["BudsCore", "BudsUI"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "BudsCoreTests",
            dependencies: ["BudsCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
