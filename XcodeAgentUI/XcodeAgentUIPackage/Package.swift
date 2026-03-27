// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "XcodeAgentUIPackage",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "XcodeAgentUICore", targets: ["XcodeAgentUICore"]),
    .library(name: "XcodeAgentUIFeatures", targets: ["XcodeAgentUIFeatures"]),
    .library(name: "XcodeAgentUIAppShell", targets: ["XcodeAgentUIAppShell"]),
  ],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.6.0"),
    .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-navigation", from: "2.3.0"),
  ],
  targets: [
    .target(
      name: "XcodeAgentUICore",
      dependencies: [
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "DependenciesMacros", package: "swift-dependencies"),
        .product(name: "Sharing", package: "swift-sharing"),
        .product(name: "SwiftNavigation", package: "swift-navigation"),
        .product(name: "SwiftUINavigation", package: "swift-navigation"),
      ]
    ),
    .target(
      name: "XcodeAgentUIFeatures",
      dependencies: [
        "XcodeAgentUICore",
      ]
    ),
    .target(
      name: "XcodeAgentUIAppShell",
      dependencies: [
        "XcodeAgentUICore",
        "XcodeAgentUIFeatures",
      ]
    ),
    .testTarget(
      name: "XcodeAgentUICoreTests",
      dependencies: [
        "XcodeAgentUICore",
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
      ]
    ),
  ]
)
