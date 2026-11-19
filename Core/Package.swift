// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "PassArcCore",
  platforms: [.macOS(.v15)],
  products: [.library(name: "PassArcCore", targets: ["PassArcCore"])],
  targets: [
    .target(name: "PassArcCore"),
    .testTarget(name: "PassArcCoreTests", dependencies: ["PassArcCore"]),
  ]
)
