// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SilentLightTrackpad",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/Kyome22/OpenMultitouchSupport.git", from: "4.0.0")
    ],
    targets: [
        .executableTarget(
            name: "SilentLightTrackpad",
            dependencies: ["OpenMultitouchSupport"],
            path: "Sources"
        )
    ]
)
