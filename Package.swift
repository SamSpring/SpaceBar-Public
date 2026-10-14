// swift-tools-version: 6.0
import PackageDescription
import Foundation

// Local development cannot replace itself with public builds. Release builders
// explicitly opt in to the separately embedded updater.
let updateChannel = ProcessInfo.processInfo.environment["SPACEBAR_UPDATE_CHANNEL"] ?? "development"
let usesSparkle = updateChannel == "public" || updateChannel == "test"
let updateDependencies: [Target.Dependency] = usesSparkle
    ? ["SpacersCore", .product(name: "Sparkle", package: "Sparkle")] : ["SpacersCore"]
let updateDefines: [SwiftSetting] = usesSparkle ? [.define("SPACEBAR_SPARKLE_UPDATES")] : []
let updateLinkerSettings: [LinkerSetting] = usesSparkle
    ? [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])] : []

let package = Package(
    name: "SpaceBar",
    platforms: [.macOS("27.0")],
    products: [.executable(name: "SpaceBar", targets: ["SpacersApp"])],
    // Sparkle 2.10.0, pinned to the upstream release commit.
    dependencies: usesSparkle ? [.package(url: "https://github.com/sparkle-project/Sparkle", revision: "eef1a539a373c1f1a320624b1130fc5de7b2e100")] : [],
    targets: [
        .target(name: "SpacersCore"),
        .target(name: "SpaceBarUpdates", dependencies: updateDependencies, swiftSettings: updateDefines),
        .executableTarget(name: "SpacersApp", dependencies: ["SpacersCore", "SpaceBarUpdates"], linkerSettings: updateLinkerSettings),
        .executableTarget(name: "SpaceBarUpdateHarness", dependencies: ["SpacersCore", "SpaceBarUpdates"],
                          path: "Tests/UpdateHarness", linkerSettings: updateLinkerSettings),
        .testTarget(name: "SpacersCoreTests", dependencies: ["SpacersCore"])
    ]
)
