// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DeskpouchGallery",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DeskpouchGallery", targets: ["DeskpouchGallery"]),
    ],
    dependencies: [
        .package(path: "../DeskpouchCore"),
    ],
    targets: [
        .target(
            name: "DeskpouchGallery",
            dependencies: [
                .product(name: "DeskpouchCore", package: "DeskpouchCore"),
            ]
        ),
        .testTarget(
            name: "DeskpouchGalleryTests",
            dependencies: ["DeskpouchGallery"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
