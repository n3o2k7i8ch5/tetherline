// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tetherline",
    platforms: [.macOS(.v14)],
    products: [.library(name: "TetherlineCore", targets: ["TetherlineCore"])],
    targets: [
        .target(name: "TetherlineCore"),
        .testTarget(name: "TetherlineCoreTests", dependencies: ["TetherlineCore"])
    ]
)

