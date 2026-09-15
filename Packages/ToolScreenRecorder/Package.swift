// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ToolScreenRecorder",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ToolScreenRecorder", targets: ["ToolScreenRecorder"]),
    ],
    dependencies: [
        .package(path: "../DeskpouchCore"),
    ],
    targets: [
        .target(
            name: "ToolScreenRecorder",
            dependencies: [
                .product(name: "DeskpouchCore", package: "DeskpouchCore"),
            ]
        ),
        .testTarget(
            name: "ToolScreenRecorderTests",
            dependencies: ["ToolScreenRecorder"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
