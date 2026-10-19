// swift-tools-version: 6.0
import PackageDescription

// Two targets on purpose:
// - AOUHubCore: domain, data and security logic on Foundation only, so
//   `swift test` runs it on Linux/WSL without an iPhone or the iOS SDK.
// - AOUHub: the SwiftUI app (presentation + LocalAuthentication), built and
//   signed by xtool. Shared resources are NOT copied here: xtool.yml bundles
//   ../shared/* straight into the .app.
let package = Package(
    name: "AOUHub",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AOUHub", targets: ["AOUHub"]),
    ],
    targets: [
        .target(name: "AOUHubCore"),
        .target(name: "AOUHub", dependencies: ["AOUHubCore"]),
        .testTarget(name: "AOUHubCoreTests", dependencies: ["AOUHubCore"]),
    ],
    swiftLanguageModes: [.v5]
)
