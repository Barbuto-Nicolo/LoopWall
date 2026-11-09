// swift-tools-version:5.9
import PackageDescription

// Deployment target: macOS 15 (previous release relative to the installed macOS 26).
let package = Package(
    name: "LoopWall",
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(name: "LoopWall", path: "Sources/LoopWall")
    ]
)
