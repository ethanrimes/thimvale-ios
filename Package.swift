// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThimvaleCore",
    platforms: [.macOS(.v14), .iOS(.v18)],
    products: [.library(name: "ThimvaleCore", targets: ["ThimvaleCore"])],
    targets: [
        .target(name: "ThimvaleCore", path: "Sources/Core", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "ThimvaleCoreTests", dependencies: ["ThimvaleCore"], path: "Tests/Core")
    ],
    swiftLanguageModes: [.v5]
)
