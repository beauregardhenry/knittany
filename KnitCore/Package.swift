// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KnitCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "KnitCore", targets: ["KnitCore"]),
        .library(name: "KnitRender", targets: ["KnitRender"]),
        .library(name: "KnitImport", targets: ["KnitImport"]),
        .executable(name: "knit", targets: ["knit"]),
    ],
    targets: [
        .target(name: "KnitCore"),
        .target(name: "KnitRender", dependencies: ["KnitCore"]),
        .target(name: "KnitImport", dependencies: ["KnitCore"]),
        .executableTarget(name: "knit", dependencies: ["KnitCore", "KnitRender", "KnitImport"]),
        .testTarget(
            name: "KnitCoreTests",
            dependencies: ["KnitCore", "KnitRender", "KnitImport"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
