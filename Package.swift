// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Rift",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "RiftCore", targets: ["RiftCore"]),
        .executable(name: "Rift", targets: ["Rift"]),
    ],
    dependencies: [
        .package(path: "../iUX-MacOS"),
    ],
    targets: [
        .target(
            name: "RiftCore",
            dependencies: ["iUX-MacOS"],
            path: "Sources/RiftCore"
        ),
        .executableTarget(
            name: "Rift",
            dependencies: ["RiftCore"],
            path: "Sources/Rift"
        ),
        .testTarget(
            name: "RiftCoreTests",
            dependencies: ["RiftCore"],
            path: "Tests/RiftCoreTests"
        ),
    ]
)
