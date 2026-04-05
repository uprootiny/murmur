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
            dependencies: ["MurmurCore"]
        ),
        .target(
            name: "MurmurCore",
            dependencies: ["CSQLite"],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("Vision", .when(platforms: [.macOS])),
                .linkedFramework("Speech", .when(platforms: [.macOS])),
                .linkedFramework("ScreenCaptureKit", .when(platforms: [.macOS])),
            ]
        ),
        .systemLibrary(
            name: "CSQLite"
        ),
        .testTarget(
            name: "MurmurCoreTests",
            dependencies: ["MurmurCore"]
        )
    ]
)
