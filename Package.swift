// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hunter",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Hunter", targets: ["Hunter"])
    ],
    targets: [
        .executableTarget(
            name: "Hunter",
            path: "Sources/Hunter",
            resources: [
                .copy("Resources")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "HunterTests",
            dependencies: ["Hunter"],
            path: "Tests/HunterTests"
        )
    ]
)
