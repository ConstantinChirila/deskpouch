// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DeskpouchCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DeskpouchCore", targets: ["DeskpouchCore"]),
    ],
    targets: [
        .target(
            name: "DeskpouchCore",
            resources: [.copy("Resources/Fonts"), .copy("Resources/Brand")]
        ),
        .testTarget(
            name: "DeskpouchCoreTests",
            dependencies: ["DeskpouchCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
