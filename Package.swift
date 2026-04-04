// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Murmur",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Murmur", targets: ["Murmur"])
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            providers: [.apt(["libsqlite3-dev"]), .brew(["sqlite3"])]
        ),
        .executableTarget(
            name: "Murmur",
            dependencies: ["CSQLite"],
            path: "Sources/Murmur",
            resources: [
                .process("Info.plist")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Vision"),
                .linkedFramework("Speech"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ApplicationServices"),
            ]
        )
    ]
)
