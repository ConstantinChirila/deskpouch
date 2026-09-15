// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ToolVoice",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ToolVoice", targets: ["ToolVoice"]),
    ],
    dependencies: [
        .package(path: "../DeskpouchCore"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4"),
    ],
    targets: [
        .target(
            name: "ToolVoice",
            dependencies: [
                .product(name: "DeskpouchCore", package: "DeskpouchCore"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
