// swift-tools-version: 6.0
import PackageDescription
import Foundation

let probeInfoPlist = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Resources/BudsProbe-Info.plist").path

let package = Package(
    name: "BudsBar",
    platforms: [.macOS("27.2")],
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
            resources: [.copy("Resources/MenuBarMonogram.png")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Headless diagnostic that exercises the same protocol code the app uses.
        .executableTarget(
            name: "BudsProbe",
            dependencies: ["BudsCore"],
            swiftSettings: [.swiftLanguageMode(.v6)],
            // A standalone executable needs its own Bluetooth usage description.
            linkerSettings: [.unsafeFlags([
                "-Xlinker", "-sectcreate",
                "-Xlinker", "__TEXT",
                "-Xlinker", "__info_plist",
                "-Xlinker", probeInfoPlist
            ])]
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
