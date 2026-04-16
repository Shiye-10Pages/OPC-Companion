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
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Speech"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("Security"),
            ]
        ),
        .testTarget(
            name: "OPCCompanionTests",
            dependencies: ["OPCCompanion"],
            path: "Tests/OPCCompanionTests"
        )
    ]
)
