// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Keymote",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SriVibeCore", targets: ["SriVibeCore"]),
        .executable(name: "Keymote", targets: ["SriVibe"])
    ],
    targets: [
        .target(name: "SriVibeCore"),
        .executableTarget(name: "SriVibe", dependencies: ["SriVibeCore"]),
        .testTarget(name: "SriVibeCoreTests", dependencies: ["SriVibeCore"])
    ]
)
