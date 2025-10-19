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
            sources: ["NovaSocialApp.swift", "Views", "ViewModels"],
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
            ]
        ),
    ]
)
