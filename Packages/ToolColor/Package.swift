// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ToolColor",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ToolColor", targets: ["ToolColor"]),
    ],
    dependencies: [
        .package(path: "../DeskpouchCapture"),
        .package(path: "../DeskpouchCore"),
    ],
    targets: [
        .target(
            name: "ToolColor",
            dependencies: [
                .product(name: "DeskpouchCapture", package: "DeskpouchCapture"),
                .product(name: "DeskpouchCore", package: "DeskpouchCore"),
            ]
        ),
        .testTarget(
            name: "ToolColorTests",
            dependencies: ["ToolColor"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
