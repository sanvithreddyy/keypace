// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KeypaceCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "KeypaceCore", targets: ["KeypaceCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
    ],
    targets: [
        .target(name: "KeypaceCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "KeypaceCoreTests", dependencies: ["KeypaceCore"]),
    ]
)
