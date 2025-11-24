// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Swift target
private let name: String = "SPFKAudio"

// C/C++ target
private let nameC: String = "\(name)C"

private let platforms: [PackageDescription.SupportedPlatform]? = [
    .macOS(.v12)
]

private let products: [PackageDescription.Product] = [
    .library(
        name: name,
        targets: [name, nameC]
    )
]

private let dependencies: [PackageDescription.Package.Dependency] = [
    .package(name: "SPFKTesting", path: "../SPFKTesting"),
    .package(name: "SPFKUtils", path: "../SPFKUtils"),
    .package(name: "SPFKMetadata", path: "../SPFKMetadata"),
    .package(name: "SPFKTime", path: "../SPFKTime"),
    .package(name: "SPFKAudioHardware", path: "../SPFKAudioHardware"),
    .package(name: "SPFKSoX", path: "../SPFKSoX"),
    .package(name: "SPFKLoudness", path: "../SPFKLoudness"),

]

private let targets: [PackageDescription.Target] = [
    // Swift
    .target(
        name: name,
        dependencies: [
            .target(name: nameC),
            .byNameItem(name: "SPFKUtils", condition: nil),
            .byNameItem(name: "SPFKMetadata", condition: nil),
            .byNameItem(name: "SPFKTime", condition: nil),
            .byNameItem(name: "SPFKAudioHardware", condition: nil),
            .byNameItem(name: "SPFKSoX", condition: nil),
            .byNameItem(name: "SPFKLoudness", condition: nil),

        ]
    ),
    
    // C
    .target(
        name: nameC,
        dependencies: [
            .byNameItem(name: "SPFKMetadata", condition: nil),
            .byNameItem(name: "SPFKSoX", condition: nil),
            .byNameItem(name: "SPFKLoudness", condition: nil),
        ],
        publicHeadersPath: "include",
        cSettings: [
            .headerSearchPath("include_private")
        ],
        cxxSettings: [
            .headerSearchPath("include_private")
        ]
    ),


    .testTarget(
        name: "\(name)Tests",
        dependencies: [
            .byNameItem(name: name, condition: nil),
            .byNameItem(name: nameC, condition: nil),
            .byNameItem(name: "SPFKTesting", condition: nil)
        ],
        resources: [
            .process("Resources")
        ]
    )
]

let package = Package(
    name: name,
    defaultLocalization: "en",
    platforms: platforms,
    products: products,
    dependencies: dependencies,
    targets: targets,
    cxxLanguageStandard: .cxx20
)
