// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ToolCalendar",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ToolCalendar", targets: ["ToolCalendar"]),
    ],
    dependencies: [
        .package(path: "../DeskpouchCore"),
    ],
    targets: [
        .target(
            name: "ToolCalendar",
            dependencies: [
                .product(name: "DeskpouchCore", package: "DeskpouchCore"),
            ]
        ),
        .testTarget(
            name: "ToolCalendarTests",
            dependencies: ["ToolCalendar"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
