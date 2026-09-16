// swift-tools-version: 6.0
import PackageDescription

/// Shared capture pieces for tools that grab the screen: the region / window / screen picker, capture geometry and
/// the ScreenCaptureKit content lookup. Depends on Core only and never on a tool.
let package = Package(
    name: "DeskpouchCapture",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DeskpouchCapture", targets: ["DeskpouchCapture"]),
    ],
    dependencies: [
        .package(path: "../DeskpouchCore"),
    ],
    targets: [
        .target(
            name: "DeskpouchCapture",
            dependencies: [
                .product(name: "DeskpouchCore", package: "DeskpouchCore"),
            ]
        ),
        .testTarget(
            name: "DeskpouchCaptureTests",
            dependencies: ["DeskpouchCapture"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
