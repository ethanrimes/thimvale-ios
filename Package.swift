// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PocketMindCore",
    platforms: [.macOS(.v14), .iOS(.v18)],
    products: [.library(name: "PocketMindCore", targets: ["PocketMindCore"])],
    targets: [
        .target(name: "PocketMindCore", path: "Sources/Core", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "PocketMindCoreTests", dependencies: ["PocketMindCore"], path: "Tests/Core")
    ],
    swiftLanguageModes: [.v5]
)
