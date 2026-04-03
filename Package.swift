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
        .executableTarget(
            name: "Murmur",
            path: "Sources/Murmur",
            resources: [
                .process("Info.plist")
            ]
        )
    ]
)
