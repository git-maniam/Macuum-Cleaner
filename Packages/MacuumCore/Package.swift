// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacuumCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MacuumCore", targets: ["MacuumCore"])
    ],
    targets: [
        .target(name: "MacuumCore"),
        .testTarget(name: "MacuumCoreTests", dependencies: ["MacuumCore"])
    ]
)
