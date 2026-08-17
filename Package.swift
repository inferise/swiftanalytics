// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "InferiseAnalytics",
    platforms: [
        .macOS("10.15"),
        .iOS("13.0"),
        .tvOS("13.0"),
        .watchOS("7.1"),
        .visionOS("1.0")
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "InferiseAnalytics",
            targets: ["InferiseAnalytics"]),
    ],
    // No external dependencies: Sovran and JSONSafeEncoding are vendored under
    // Sources/. See the VENDORED.md in each for origin, version, and license.
    dependencies: [],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "Sovran",
            exclude: ["LICENSE", "VENDORED.md"]
        ),
        .target(
            name: "JSONSafeEncoding",
            exclude: ["LICENSE", "VENDORED.md"]
        ),
        .target(
            name: "InferiseAnalytics",
            dependencies: [
                "Sovran",
                "JSONSafeEncoding"
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "InferiseAnalytics-Tests",
            dependencies: ["InferiseAnalytics"]
        ),
    ]
)
