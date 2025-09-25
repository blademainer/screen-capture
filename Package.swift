// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MacScreenCapture",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "MacScreenCapture",
            targets: ["MacScreenCapture"]
        ),
    ],
    dependencies: [
        // 如果需要外部依赖，可以在这里添加
        // .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "MacScreenCapture",
            dependencies: [
                // 添加依赖
            ],
            path: "MacScreenCapture",
            resources: [
                .process("Assets.xcassets"),
                .process("Preview Content")
            ]
        ),
        .testTarget(
            name: "MacScreenCaptureTests",
            dependencies: ["MacScreenCapture"],
            path: "MacScreenCaptureTests"
        ),
    ]
)