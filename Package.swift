// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SilentLightTrackpad",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "SilentLightTrackpad",
            path: "Sources"
        )
    ]
)
