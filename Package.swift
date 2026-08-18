// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "OpenVale",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "OpenVale", targets: ["OpenVale"])
    ],
    targets: [
        .executableTarget(
            name: "OpenVale",
            path: "Sources/OpenVale"
        ),
        .testTarget(
            name: "OpenValeTests",
            dependencies: ["OpenVale"],
            path: "Tests/OpenValeTests"
        )
    ]
)
