// swift-tools-version: 5.9
//
// macOS CLI demo: BamlAnalyzer
//
// Run:
//   OPENROUTER_API_KEY=sk-or-... \
//   BAML_LIBRARY_PATH=engine/target/aarch64-apple-darwin/release/libbaml_cffi.dylib \
//   swift run
//
// Or pipe text from stdin:
//   echo "some text..." | \
//   OPENROUTER_API_KEY=sk-or-... \
//   BAML_LIBRARY_PATH=... \
//   swift run BamlAnalyzer --stdin

import PackageDescription

let package = Package(
    name: "BamlAnalyzer",
    platforms: [.macOS(.v12)],
    dependencies: [
        // Local path to language_client_swift (three levels up from docs/demos/macos/)
        .package(path: "../../../"),
    ],
    targets: [
        // Generated BAML client (TextAnalysis schema)
        .target(
            name: "BamlClient",
            dependencies: [
                .product(name: "BamlSwift", package: "language_client_swift"),
            ],
            path: "baml_client"
        ),
        // CLI executable
        .executableTarget(
            name: "BamlAnalyzer",
            dependencies: ["BamlClient"],
            path: "Sources/BamlAnalyzer"
        ),
    ]
)
