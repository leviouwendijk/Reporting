// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ReportingTests",
    platforms: [.macOS(.v13)],
    products: [
        .executable(
            name: "t_reporting",
            targets: ["ReportingTesting"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/leviouwendijk/DSL.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/Search.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/Testing.git", branch: "master"),
        .package(path: ".."),
    ],
    targets: [
        .executableTarget(
            name: "ReportingTesting",
            dependencies: [
                .product(name: "Reporting", package: "Reporting"),
                .product(name: "Search", package: "Search"),
                .product(name: "DSL", package: "DSL"),
                .product(name: "Testing", package: "Testing"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
