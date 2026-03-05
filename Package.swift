// swift-tools-version: 6.2
// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import PackageDescription

let package = Package(
    name: "spfk-audio-conversion",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "SPFKAudioConversion",
            targets: ["SPFKAudioConversion"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/ryanfrancesconi/spfk-base", from: "0.0.5"),
        .package(url: "https://github.com/ryanfrancesconi/spfk-audio-base", from: "0.0.6"),
        .package(url: "https://github.com/ryanfrancesconi/spfk-metadata", from: "0.0.9"),
        .package(url: "https://github.com/ryanfrancesconi/spfk-sox", from: "0.0.1"),
        .package(url: "https://github.com/ryanfrancesconi/spfk-testing", from: "0.0.5"),
        .package(url: "https://github.com/ryanfrancesconi/spfk-utils", from: "0.0.8"),

    ],
    targets: [
        .target(
            name: "SPFKAudioConversion",
            dependencies: [
                .product(name: "SPFKBase", package: "spfk-base"),
                .product(name: "SPFKAudioBase", package: "spfk-audio-base"),
                .product(name: "SPFKMetadata", package: "spfk-metadata"),
                .product(name: "SPFKSoX", package: "spfk-sox"),
                .product(name: "SPFKUtils", package: "spfk-utils"),
            ],
        ),

        .testTarget(
            name: "SPFKAudioConversionTests",
            dependencies: [
                .targetItem(name: "SPFKAudioConversion", condition: nil),
                .product(name: "SPFKTesting", package: "spfk-testing"),
            ],
        ),
    ],
    cxxLanguageStandard: .cxx20
)
