// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StageOne",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "StageOne", targets: ["StageOneApp"]),
        .executable(name: "stage", targets: ["stage"]),
        .library(name: "StageOneCore", targets: ["StageOneCore"]),
        .library(name: "WindowKit", targets: ["WindowKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        // Pure Swift: models, geometry, layouts, scenes, identity. No AppKit, so it is unit-testable anywhere.
        .target(name: "StageOneCore"),
        // macOS window engine: CGWindowList, Accessibility (AXUIElement), ScreenCaptureKit.
        .target(name: "WindowKit", dependencies: ["StageOneCore"]),
        // The LSUIElement menu bar app.
        .executableTarget(name: "StageOneApp", dependencies: ["StageOneCore", "WindowKit"]),
        // The `stage` command-line tool. Talks to the app over a local socket.
        .executableTarget(name: "stage", dependencies: [
            "StageOneCore",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),
        .testTarget(name: "StageOneCoreTests", dependencies: ["StageOneCore"]),
    ]
)
