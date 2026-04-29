// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "vow",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(name: "VowCore", targets: ["VowCore"]),
        .library(name: "VowUI", targets: ["VowUI"])
    ],
    targets: [
        .target(
            name: "VowCore",
            path: "Sources/VowCore"
        ),
        .target(
            name: "VowUI",
            dependencies: ["VowCore"],
            path: "Sources/VowUI"
        )
    ]
)
