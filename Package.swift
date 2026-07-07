// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScreenCapture",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ScreenCapture", targets: ["ScreenCaptureApp"])
    ],
    targets: [
        .executableTarget(
            name: "ScreenCaptureApp",
            path: "Sources/ScreenCaptureApp",
            resources: [
                .process("../../Resources")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("UserNotifications")
            ]
        )
    ]
)
