// swift-tools-version: 5.9
//
// DISTRIBUTION PACKAGE — used by the boundaryml/baml-swift mirror repo.
//
// This file is NOT used for local development (see Package.swift for that).
// CI runs scripts/stamp-distribution-package.sh to substitute BAML_VERSION
// and BAML_SPM_CHECKSUM before pushing to the mirror repo.
//
// Users add this package via:
//   .package(url: "https://github.com/boundaryml/baml-swift.git", from: "BAML_VERSION")

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
        // Pre-compiled Rust CFFI static library for all platforms/archs.
        // SPM downloads and caches this automatically.
        .binaryTarget(
            name: "BamlCFFI",
            url: "https://github.com/boundaryml/baml/releases/download/BAML_VERSION/BamlCFFI.xcframework.zip",
            checksum: "BAML_SPM_CHECKSUM"
        ),

        .target(
            name: "BamlSwift",
            dependencies: [
                "BamlCFFI",
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            path: "Sources/BamlSwift"
        ),
    ]
)
