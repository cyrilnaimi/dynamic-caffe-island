// swift-tools-version: 5.9
//
// Dynamic Caffe Island — SwiftPM workspace for the plugin contract and the
// two built-in profiles. The app target (`App/`) lives in the Xcode project
// at the repo root and consumes this package.

import PackageDescription

let package = Package(
    name: "DynamicCaffeIslandPackages",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "ProfileKit", targets: ["ProfileKit"]),
        .library(name: "AnimationKit", targets: ["AnimationKit"]),
        .library(name: "IslandCore", targets: ["IslandCore"]),
        .library(name: "PowerAssertions", targets: ["PowerAssertions"]),
        .library(name: "SleepClock", targets: ["SleepClock"]),
        .library(name: "BuiltInProfiles", targets: ["BuiltInProfiles"]),
    ],
    targets: [
        .target(name: "ProfileKit"),
        .target(name: "AnimationKit"),
        .target(
            name: "IslandCore",
            dependencies: ["ProfileKit"]
        ),
        .target(name: "PowerAssertions"),
        .target(name: "SleepClock"),
        .target(
            name: "BuiltInProfiles",
            dependencies: [
                "ProfileKit",
                "AnimationKit",
                "IslandCore",
                "PowerAssertions",
                "SleepClock",
            ],
            path: "Profiles"
        ),

        // Test targets (Tests/ lives at repo root per plan.md).
        .testTarget(
            name: "UnitTests",
            dependencies: [
                "ProfileKit",
                "AnimationKit",
                "IslandCore",
                "PowerAssertions",
                "SleepClock",
                "BuiltInProfiles",
            ],
            path: "Tests/UnitTests"
        ),
        .testTarget(
            name: "ContractTests",
            dependencies: [
                "ProfileKit",
                "AnimationKit",
                "IslandCore",
                "BuiltInProfiles",
            ],
            path: "Tests/ContractTests"
        ),
        .testTarget(
            name: "IntegrationTests",
            dependencies: [
                "ProfileKit",
                "AnimationKit",
                "IslandCore",
                "PowerAssertions",
                "SleepClock",
                "BuiltInProfiles",
            ],
            path: "Tests/IntegrationTests"
        ),
    ]
)
