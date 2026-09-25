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
        // Exact: the Xcode build has no committed lockfile, and this code ships in a signed app that holds the
        // Microphone, Screen Recording and Accessibility grants. Updates are taken by hand, after a look.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.15.7"),
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
