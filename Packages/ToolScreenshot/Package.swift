// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ToolScreenshot",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ToolScreenshot", targets: ["ToolScreenshot"]),
    ],
    dependencies: [
        .package(path: "../DeskpouchCapture"),
        .package(path: "../DeskpouchCore"),
    ],
    targets: [
        .target(
            name: "ToolScreenshot",
            dependencies: [
                .product(name: "DeskpouchCapture", package: "DeskpouchCapture"),
                .product(name: "DeskpouchCore", package: "DeskpouchCore"),
            ]
        ),
        .testTarget(
            name: "ToolScreenshotTests",
            dependencies: ["ToolScreenshot"],
            resources: [.copy("Golden")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
