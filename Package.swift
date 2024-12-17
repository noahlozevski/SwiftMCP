// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftMCP",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "SwiftMCP",
            targets: ["SwiftMCP"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SwiftMCP",
            dependencies: []
        ),
        .testTarget(
            name: "SwiftMCPTests",
            dependencies: [
                "SwiftMCP"
            ]
        ),
    ]
)
