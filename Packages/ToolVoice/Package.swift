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
        // Pre-1.0: minor releases may break the API, so only patch updates are taken automatically.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", .upToNextMinor(from: "0.15.7")),
    ],
    targets: [
        .target(
            name: "ToolVoice",
            dependencies: [
                .product(name: "DeskpouchCore", package: "DeskpouchCore"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
        .testTarget(
            name: "ToolVoiceTests",
            dependencies: ["ToolVoice"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
