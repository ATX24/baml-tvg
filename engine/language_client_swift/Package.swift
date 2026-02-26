// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BamlSwift",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(name: "BamlSwift", targets: ["BamlSwift"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-protobuf.git",
            from: "1.28.0"
        ),
    ],
    targets: [
        // Pre-compiled Rust CFFI library as XCFramework (iOS)
        // On macOS, the dylib is downloaded at runtime (Go-style)
        // For local development, use the systemLibrary target instead
        .systemLibrary(
            name: "BamlCFFI",
            path: "include",
            pkgConfig: nil,
            providers: []
        ),
        .target(
            name: "BamlSwift",
            dependencies: [
                "BamlCFFI",
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            path: "Sources/BamlSwift"
        ),
        .testTarget(
            name: "BamlSwiftTests",
            dependencies: ["BamlSwift"],
            path: "Tests/BamlSwiftTests"
        ),
    ]
)
