// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KnitCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "KnitCore", targets: ["KnitCore"]),
        .executable(name: "knit", targets: ["knit"]),
    ],
    targets: [
        .target(name: "KnitCore"),
        .executableTarget(name: "knit", dependencies: ["KnitCore"]),
        .testTarget(
            name: "KnitCoreTests",
            dependencies: ["KnitCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
