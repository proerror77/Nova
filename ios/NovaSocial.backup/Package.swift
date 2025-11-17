// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NovaSocial",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "NovaSocial",
            targets: ["NovaSocial"]
        ),
    ],
    targets: [
        .target(
            name: "NovaSocial",
            dependencies: [],
            path: ".",
            exclude: [
                "Tests",
                "Documentation",
                "DesignSystem",
                "LocalData",
                "Network",
                "Localization",
                "MediaKit",
                "Accessibility",
                "DeepLinking",
                "Config",
                "Resources",
                "Examples",
                "Utils",
                "App"
            ],
            sources: ["NovaSocialApp.swift", "Views", "ViewModels"]
        ),
    ]
)
