// swift-tools-version: 6.0
//
// Package.swift — SPM dependency manifest for XcodeAgentUI
//
// HOW TO USE:
// In Xcode, go to File > Add Package Dependencies and add each URL below.
// Alternatively, reference this local package from the Xcode project.

import PackageDescription

let package = Package(
  name: "XcodeAgentUI",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "XcodeAgentUI", targets: ["XcodeAgentUI"]),
  ],
  dependencies: [
    // Point-Free: Dependency injection & testing
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.6.0"),
    // Point-Free: Cross-platform state sharing & persistence
    .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.0.0"),
    // Point-Free: Deep linking, navigation state, alerts
    .package(url: "https://github.com/pointfreeco/swift-navigation", from: "2.3.0"),
  ],
  targets: [
    .target(
      name: "XcodeAgentUI",
      dependencies: [
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "DependenciesMacros", package: "swift-dependencies"),
        .product(name: "Sharing", package: "swift-sharing"),
        .product(name: "SwiftNavigation", package: "swift-navigation"),
        .product(name: "SwiftUINavigation", package: "swift-navigation"),
      ]
    ),
    .testTarget(
      name: "XcodeAgentUITests",
      dependencies: [
        "XcodeAgentUI",
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
      ]
    ),
  ]
)
