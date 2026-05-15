// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "UltimateOrganizer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "UltimateOrganizerCore",
            targets: ["UltimateOrganizerCore"]
        ),
        .executable(
            name: "UltimateOrganizer",
            targets: ["UltimateOrganizer"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0")
    ],
    targets: [
        .target(
            name: "UltimateOrganizerCore"
        ),
        .executableTarget(
            name: "UltimateOrganizer",
            dependencies: [
                "UltimateOrganizerCore",
                .product(name: "Sparkle", package: "Sparkle")
            ]
        ),
        .testTarget(
            name: "UltimateOrganizerCoreTests",
            dependencies: ["UltimateOrganizerCore", "UltimateOrganizer"]
        )
    ]
)
