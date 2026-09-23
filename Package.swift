// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WattHound",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "WattHound", targets: ["WattHound"])
    ],
    targets: [
        .executableTarget(
            name: "WattHound",
            path: "Sources/WattHound",
            resources: [
                .copy("Resources")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "WattHoundTests",
            dependencies: ["WattHound"],
            path: "Tests/WattHoundTests"
        )
    ]
)
