// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Murmur",
    platforms: [
        .macOS(.v10_13)
    ],
    products: [
        .executable(name: "MurmurApp", targets: ["MurmurApp"])
    ],
    targets: [
        .executableTarget(
            name: "MurmurApp",
            dependencies: ["MurmurCore"],
            resources: [.process("../Resources")]
        ),
        .target(
            name: "MurmurCore",
            dependencies: []
        ),
        .testTarget(
            name: "MurmurCoreTests",
            dependencies: ["MurmurCore"]
        )
    ]
)
