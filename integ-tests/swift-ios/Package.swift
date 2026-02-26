// swift-tools-version: 5.9
//
// iOS integration test package for BamlSwift.
// Uses the XCFramework (static linking) — no BAML_LIBRARY_PATH needed.
// Run with:
//   xcodebuild test \
//     -scheme BamlIOSIntegTests \
//     -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' \
//     -testEnvironmentVariables "OPENROUTER_API_KEY=sk-or-..."

import PackageDescription

let package = Package(
    name: "BamlIOSIntegTests",
    platforms: [
        .iOS(.v15),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-protobuf.git",
            from: "1.28.0"
        ),
    ],
    targets: [
        // Local XCFramework (static libs for ios-arm64, ios-sim, macos)
        // Symlink: BamlCFFI.xcframework -> ../../engine/language_client_swift/BamlCFFI.xcframework
        .binaryTarget(
            name: "BamlCFFI",
            path: "BamlCFFI.xcframework"
        ),

        // BamlSwift sources — symlinked from engine/language_client_swift/Sources/BamlSwift
        // On iOS: DynamicLoader is compiled out (#if os(macOS)), FFI calls C symbols directly
        .target(
            name: "BamlSwift",
            dependencies: [
                "BamlCFFI",
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            path: "Sources/BamlSwift"
        ),

        // Generated BAML client — symlinked from integ-tests/swift/baml_client
        .target(
            name: "BamlClient",
            dependencies: ["BamlSwift"],
            path: "Sources/BamlClient"
        ),

        // iOS simulator integration tests
        .testTarget(
            name: "BamlIOSIntegTests",
            dependencies: ["BamlClient"],
            path: "Tests/BamlIOSIntegTests"
        ),
    ]
)
