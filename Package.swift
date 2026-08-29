// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Dhun",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Dhun",
            path: "Sources/Dhun",
            resources: [
                .copy("Resources/Shaders.metal")
            ]
        )
    ]
)
