// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "JumpKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "JumpKit", targets: ["JumpKit"]),
    ],
    targets: [
        .target(
            name: "JumpKit",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        // Developer tool: measures scan latency against a running app.
        .executableTarget(
            name: "jump-bench",
            dependencies: ["JumpKit"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "JumpKitTests",
            dependencies: ["JumpKit"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
