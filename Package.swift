// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HoverMind",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/awslabs/aws-sdk-swift", from: "1.6.0"),
        .package(url: "https://github.com/smithy-lang/smithy-swift", from: "0.194.0"),
    ],
    targets: [
        .executableTarget(
            name: "HoverMind",
            dependencies: [
                .product(name: "AWSBedrockRuntime", package: "aws-sdk-swift"),
                .product(name: "Smithy", package: "smithy-swift"),
            ],
            path: "Sources/HoverMind"
        ),
        .testTarget(
            name: "HoverMindTests",
            dependencies: ["HoverMind"],
            path: "Tests/HoverMindTests"
        ),
    ]
)
