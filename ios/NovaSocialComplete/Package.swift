// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NovaSocial",
    platforms: [
        .iOS(.v16)
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "NovaSocial",
            dependencies: [],
            path: "Sources"
        )
    ]
)
