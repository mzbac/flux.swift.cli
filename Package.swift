// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "flux.swift.cli",
  platforms: [.macOS(.v14), .iOS(.v16)],
  dependencies: [
    .package(url: "https://github.com/mzbac/flux.swift.git", branch: "main"),
    .package(url: "https://github.com/huggingface/swift-transformers", from: "0.1.13"),
    .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    .package(url: "https://github.com/jkandzi/Progress.swift", from: "0.4.0"),
  ],
  targets: [
    .executableTarget(
      name: "flux.swift.cli",
      dependencies: [
        .product(name: "FluxSwift", package: "flux.swift"),
        .product(name: "Transformers", package: "swift-transformers"),
        .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Progress", package: "Progress.swift"),
      ])
  ]
)
