// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OPCCompanion",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "OPCCompanion",
            path: "Sources/OPCCompanion",
            resources: [
                .copy("../../Resources/notion-mcp.json")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Speech"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("UserNotifications"),
            ]
        )
    ]
)
