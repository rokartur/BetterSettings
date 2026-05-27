// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "BetterSettings",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "BetterSettings",
            targets: ["BetterSettings"]
        ),
        .executable(
            name: "better-settings-demo",
            targets: ["better-settings-demo"]
        )
    ],
    targets: [
        // macOS-native, dependency-free settings window framework.
        // macOS-style sidebar with section search + scroll-to-section navigation,
        // modeled on the BetterAudio preferences window.
        .target(
            name: "BetterSettings",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // Minimal runnable wiring example. Doubles as a compile-time API contract.
        .executableTarget(
            name: "better-settings-demo",
            dependencies: ["BetterSettings"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "BetterSettingsTests",
            dependencies: ["BetterSettings"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
