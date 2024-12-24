// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftMCP",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "SwiftMCP",
            targets: ["SwiftMCP"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/kevinhermawan/swift-json-schema.git",
            .upToNextMajor(from: "1.0.0"))
    ],
    targets: [
        .target(
            name: "SwiftMCP",
            dependencies: [
                .product(name: "JSONSchema", package: "swift-json-schema")
            ]
        ),
        .testTarget(
            name: "SwiftMCPTests",
            dependencies: [
                "SwiftMCP"
            ]
        )
    ]
)
