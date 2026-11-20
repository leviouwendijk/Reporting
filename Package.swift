// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Reporting",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "Reporting",
            targets: ["Reporting"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/leviouwendijk/DSL.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/Search.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/Math.git", branch: "master"),
    ],
    targets: [
        .target(
            name: "Reporting",
            dependencies: [
                .product(name: "DSL", package: "DSL"),
                .product(name: "Search", package: "Search"),
                .product(name: "Math", package: "Math"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
