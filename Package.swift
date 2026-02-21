// swift-tools-version: 6.2
// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import PackageDescription

let package = Package(
    name: "spfk-audio",
    defaultLocalization: "en",
    platforms: [.macOS(.v12)],
    products: [
        .library(
            name: "SPFKAudio",
            targets: ["SPFKAudio", "SPFKAudioC"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/ryanfrancesconi/spfk-tempo", from: "0.0.1"),
        .package(url: "https://github.com/ryanfrancesconi/spfk-au-host", from: "0.0.1"),
        .package(url: "https://github.com/ryanfrancesconi/spfk-audio-hardware", from: "0.0.1"),
        .package(url: "https://github.com/ryanfrancesconi/spfk-loudness", from: "0.0.1"),
        .package(url: "https://github.com/ryanfrancesconi/spfk-metadata", from: "0.0.1"),
        .package(url: "https://github.com/ryanfrancesconi/spfk-sox", from: "0.0.1"),
        .package(url: "https://github.com/ryanfrancesconi/spfk-testing", from: "0.0.1"),
        .package(url: "https://github.com/ryanfrancesconi/spfk-time", from: "0.0.1"),
        .package(url: "https://github.com/ryanfrancesconi/spfk-utils", from: "0.0.3"),
    ],
    targets: [
        .target(
            name: "SPFKAudio",
            dependencies: [
                .targetItem(name: "SPFKAudioC", condition: nil),

                .product(name: "SPFKTempo", package: "spfk-tempo"),
                .product(name: "SPFKAUHost", package: "spfk-au-host"),
                .product(name: "SPFKAudioHardware", package: "spfk-audio-hardware"),
                .product(name: "SPFKLoudness", package: "spfk-loudness"),
                .product(name: "SPFKMetadata", package: "spfk-metadata"),
                .product(name: "SPFKSoX", package: "spfk-sox"),
                .product(name: "SPFKTime", package: "spfk-time"),
                .product(name: "SPFKUtils", package: "spfk-utils"),
            ],
        ),
        .target(
            name: "SPFKAudioC",
            dependencies: [
                .product(name: "SPFKLoudness", package: "spfk-loudness"),
                .product(name: "SPFKMetadata", package: "spfk-metadata"),
                .product(name: "SPFKSoX", package: "spfk-sox"),
            ],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include_private")
            ],
            cxxSettings: [
                .headerSearchPath("include_private")
            ],
        ),
        .testTarget(
            name: "SPFKAudioTests",
            dependencies: [
                .targetItem(name: "SPFKAudio", condition: nil),
                .targetItem(name: "SPFKAudioC", condition: nil),
                .product(name: "SPFKTesting", package: "spfk-testing"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ],
        ),
    ],
    cxxLanguageStandard: .cxx20
)
