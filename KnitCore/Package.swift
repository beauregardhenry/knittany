// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KnitCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "KnitCore", targets: ["KnitCore"]),
        .library(name: "KnitRender", targets: ["KnitRender"]),
        .executable(name: "knit", targets: ["knit"]),
    ],
    targets: [
        .target(name: "KnitCore"),
        .target(name: "KnitRender", dependencies: ["KnitCore"]),
        .executableTarget(name: "knit", dependencies: ["KnitCore", "KnitRender"]),
        .testTarget(
            name: "KnitCoreTests",
            dependencies: ["KnitCore", "KnitRender"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
