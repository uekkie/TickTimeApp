// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "TickTime",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TickTime", targets: ["TickTime"])
    ],
    targets: [
        .executableTarget(
            name: "TickTime",
            path: "Sources/LocalTime"
        ),
        .testTarget(
            name: "TickTimeTests",
            dependencies: ["TickTime"],
            path: "Tests/LocalTimeTests"
        )
    ]
)
