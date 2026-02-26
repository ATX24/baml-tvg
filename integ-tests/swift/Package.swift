// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BamlIntegTests",
    platforms: [
        .macOS(.v12),
    ],
    dependencies: [
        .package(path: "../../engine/language_client_swift"),
    ],
    targets: [
        // The generated BAML client code
        .target(
            name: "BamlClient",
            dependencies: [
                .product(name: "BamlSwift", package: "language_client_swift"),
            ],
            path: "baml_client"
        ),
        // Integration tests using the generated client
        .testTarget(
            name: "BamlIntegTests",
            dependencies: ["BamlClient"],
            path: "Tests/BamlIntegTests"
        ),
    ]
)
