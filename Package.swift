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
        .package(url: "https://github.com/ryanfrancesconi/spfk-lame", from: "0.0.1"),
        .package(url: "https://github.com/ryanfrancesconi/spfk-testing", from: "0.0.5"),
        .package(url: "https://github.com/ryanfrancesconi/spfk-utils", from: "0.0.8"),
        .package(url: "https://github.com/sbooth/sndfile-binary-xcframework", from: "0.1.2"),
        .package(url: "https://github.com/sbooth/ogg-binary-xcframework", from: "0.1.3"),
        .package(url: "https://github.com/sbooth/flac-binary-xcframework", from: "0.2.0"),
        .package(url: "https://github.com/sbooth/vorbis-binary-xcframework", from: "0.1.2"),
        .package(url: "https://github.com/sbooth/opus-binary-xcframework", from: "0.2.2"),
    ],
    targets: [
        .target(
            name: "SPFKAudioConverterC",
            dependencies: [
                .product(name: "sndfile", package: "sndfile-binary-xcframework"),
                .product(name: "ogg", package: "ogg-binary-xcframework"),
                .product(name: "FLAC", package: "flac-binary-xcframework"),
                .product(name: "vorbis", package: "vorbis-binary-xcframework"),
                .product(name: "opus", package: "opus-binary-xcframework"),
                .product(name: "lame", package: "spfk-lame"),
                .product(name: "mpg123", package: "spfk-lame"),
            ],
            path: "Sources/SPFKAudioConverterC",
            publicHeadersPath: "include"
        ),

        .target(
            name: "SPFKAudioConversion",
            dependencies: [
                "SPFKAudioConverterC",
                .product(name: "SPFKBase", package: "spfk-base"),
                .product(name: "SPFKAudioBase", package: "spfk-audio-base"),
                .product(name: "SPFKMetadata", package: "spfk-metadata"),
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
