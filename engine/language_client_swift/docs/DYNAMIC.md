# Dynamic iOS Loading — Milestone 2 Plan

## Overview

Milestone 1 uses **static linking**: the entire Rust CFFI library is compiled into
`BamlCFFI.xcframework` and linked at build time. This works correctly but has two
drawbacks:

1. **Binary size**: ~112 MB added to every app that uses BAML (mostly Rust std + OpenSSL).
2. **App Store review**: large static binaries can slow App Store processing and raise
   questions during review.

Milestone 2 introduces a **dynamic framework** variant: `BamlCFFI.framework` is a
`.dylib`-backed framework that the developer embeds in their Xcode project and BAML lazy-loads
at runtime via `dlopen`. App startup is unaffected; the library loads on first use.

---

## Why dlopen Works on iOS (with caveats)

Apple Guideline 2.5.2 prohibits downloading and executing code after submission. However,
`dlopen` against a framework that is **already bundled inside the app** at submission time
is permitted. This is the same mechanism used by:

- Metal shader libraries (`.metallib`)
- Safari Content Blockers
- Various first-party Apple frameworks that defer loading

The key requirements:
- The framework **must** be present in the app bundle at App Store submission.
- It must be placed in `Shared Frameworks` (so it can be shared across app + extensions).
- The framework must **not** appear in the *Link Binary With Libraries* Xcode build phase
  (otherwise Xcode auto-links it at launch, defeating the purpose).
- Automatic linking must be disabled in Swift compiler settings
  (`OTHER_SWIFT_FLAGS = -disable-autolink-framework BamlCFFI`).

Reference: ["Lazy Loading Dynamic Libraries and Building Plugin Architectures on iOS"
(Scott Yelvington, April 2025)](https://medium.com/@cjckytxz/lazy-loading-dynamic-libraries-and-building-plugin-architectures-on-ios-challenge-accepted-a554fccdb84c)

---

## Architecture: Two Packages

| | `baml-swift` (Milestone 1) | `baml-swift-dynamic` (Milestone 2) |
|---|---|---|
| Linking | Static (`binaryTarget` XCFramework) | Dynamic (`dlopen` at first use) |
| SPM setup | Auto — SPM handles everything | Manual — developer embeds framework |
| App size impact | +112 MB | +0 MB at install; framework loaded on demand |
| iOS App Store | ✅ | ✅ (framework bundled at submission) |
| macOS | ✅ | ✅ (same `dlopen` path as existing Go/Python clients) |

---

## Phase 1: Build Dynamic XCFramework

### 1.1 Cargo: dynamic library targets

The existing `build-xcframework.sh` compiles static archives (`--crate-type=staticlib`).
For the dynamic variant, build shared libraries:

```bash
# iOS device (arm64)
cargo build --release -p baml-language-client-cffi \
  --target aarch64-apple-ios \
  --features cdylib

# iOS simulator (arm64 + x86_64 fat)
cargo build --release -p baml-language-client-cffi \
  --target aarch64-apple-ios-sim
cargo build --release -p baml-language-client-cffi \
  --target x86_64-apple-ios
lipo -create \
  target/aarch64-apple-ios-sim/release/libbaml_cffi.dylib \
  target/x86_64-apple-ios/release/libbaml_cffi.dylib \
  -output target/ios-sim-fat/libbaml_cffi.dylib

# macOS universal
lipo -create \
  target/aarch64-apple-darwin/release/libbaml_cffi.dylib \
  target/x86_64-apple-darwin/release/libbaml_cffi.dylib \
  -output target/macos-fat/libbaml_cffi.dylib
```

### 1.2 Create .framework bundles

SPM `.binaryTarget` for dynamic frameworks expects a `.framework` bundle structure, not a
bare `.dylib`. Create one per slice:

```
BamlCFFI.framework/
├── BamlCFFI               # the dylib (LC_ID_DYLIB set correctly)
├── Headers/
│   ├── baml_cffi.h
│   └── module.modulemap
└── Info.plist
```

Use `install_name_tool` to set the install name:
```bash
install_name_tool -id @rpath/BamlCFFI.framework/BamlCFFI \
  BamlCFFI.framework/BamlCFFI
```

### 1.3 Assemble XCFramework

```bash
xcodebuild -create-xcframework \
  -framework ios-arm64/BamlCFFI.framework \
  -framework ios-sim-fat/BamlCFFI.framework \
  -framework macos-fat/BamlCFFI.framework \
  -output BamlCFFI-dynamic.xcframework
zip -r BamlCFFI-dynamic.xcframework.zip BamlCFFI-dynamic.xcframework
swift package compute-checksum BamlCFFI-dynamic.xcframework.zip
```

---

## Phase 2: DynamicLoader.swift (iOS path)

The existing `DynamicLoader.swift` handles the macOS `dlopen` path. It needs an iOS branch
that loads from the app bundle's `Shared Frameworks`:

```swift
// In DynamicLoader.swift, replace the macOS-only dlopen block:

#if os(macOS)
// Existing macOS path: download from GitHub releases or BAML_LIBRARY_PATH
private func libraryPath() throws -> String { ... }
#else
// iOS path: load from app bundle (bundled at submission time)
private func libraryPath() throws -> String {
    // Try SharedFrameworks first (recommended location)
    if let sharedPath = Bundle.main.sharedFrameworksPath {
        let path = "\(sharedPath)/BamlCFFI.framework/BamlCFFI"
        if FileManager.default.fileExists(atPath: path) { return path }
    }
    // Fallback: PrivateFrameworks
    if let privatePath = Bundle.main.privateFrameworksPath {
        let path = "\(privatePath)/BamlCFFI.framework/BamlCFFI"
        if FileManager.default.fileExists(atPath: path) { return path }
    }
    throw BamlError.libraryNotFound(
        "BamlCFFI.framework not found in app bundle. " +
        "Add it to your Xcode project under Shared Frameworks and ensure " +
        "it is NOT in Link Binary With Libraries."
    )
}
#endif
```

Remove the `#if os(macOS)` guard from `DynamicLoader.load()` so it runs on iOS too.

---

## Phase 3: Package.swift for the dynamic variant

The dynamic package cannot use a `binaryTarget` that auto-links — SPM would add it to the
linker flags and defeat the lazy-load purpose. Instead:

```swift
// engine/language_client_swift_dynamic/Package.swift
targets: [
    // BamlCFFI.framework is NOT declared as an SPM target.
    // The developer adds it manually to their Xcode project.
    // See: docs/XCODE_SETUP.md

    .target(
        name: "BamlSwiftDynamic",
        dependencies: [
            .product(name: "SwiftProtobuf", package: "swift-protobuf"),
        ],
        path: "Sources/BamlSwift",
        swiftSettings: [
            // Prevent Xcode from auto-linking BamlCFFI if it's in scope
            .unsafeFlags(["-disable-autolink-framework", "BamlCFFI"])
        ]
    ),
]
```

---

## Phase 4: Developer Xcode Setup (dynamic variant)

Because SPM can't manage the embedding for the dynamic path, the developer must:

1. Download `BamlCFFI-dynamic.xcframework.zip` from the BAML GitHub release for their
   BAML version.
2. Unzip and drag `BamlCFFI.framework` (the iOS-simulator or device slice as needed) into
   **Xcode → General → Frameworks, Libraries, and Embedded Content** → set to
   **Embed Without Signing** (or **Embed & Sign** for device).
3. Move `BamlCFFI.framework` from the default *Link Binary With Libraries* build phase to
   the **Embed Frameworks** phase only.
4. Add `-disable-autolink-framework BamlCFFI` to **Other Swift Flags** in Build Settings.

Document this in `engine/language_client_swift_dynamic/docs/XCODE_SETUP.md`.

---

## Phase 5: CI Integration

Add a new job to `build-swift-release.reusable.yaml`:

```yaml
build-dynamic-xcframework:
  name: Build Dynamic XCFramework
  runs-on: macos-14
  steps:
    - uses: actions/checkout@v4
    - name: Build dynamic XCFramework
      run: bash scripts/build-xcframework-dynamic.sh
      working-directory: engine/language_client_swift
    - name: Upload artifact
      uses: actions/upload-artifact@v4
      with:
        name: BamlCFFI-dynamic-xcframework
        path: |
          engine/language_client_swift/BamlCFFI-dynamic.xcframework.zip
          engine/language_client_swift/BamlCFFI-dynamic.xcframework.zip.sha256
```

Add `BamlCFFI-dynamic.xcframework.zip` and `.sha256` to the GitHub Release upload in
`release.yml`.

---

## Phase 6: Integration Tests (dynamic / iOS)

Add an iOS simulator test job that:
1. Installs the dynamic XCFramework into the simulator app bundle's Shared Frameworks.
2. Sets `DYLD_FRAMEWORK_PATH` to include the framework directory.
3. Runs `xcodebuild test` on a new `integ-tests/swift-ios-dynamic/` package.

The test package mirrors `integ-tests/swift-ios/` but uses `BamlSwiftDynamic` instead of
`BamlSwift`.

---

## Open Questions

- **App Store validation**: Apple's bitcode requirement was dropped in Xcode 14, but App
  Store Connect may still flag unusually large dylibs. Test a submission before committing
  to this approach.
- **Code signing**: The embedded framework must be signed with the same team as the app.
  The `BamlCFFI-dynamic.xcframework` distributed on GitHub should be unsigned; the
  developer's Xcode signs it at archive time.
- **Size comparison**: Measure stripped dylib size vs static lib. ThinLTO + strip may
  reduce the dynamic binary significantly (target <30 MB per-arch).
- **arm64e**: Apple Silicon devices use `arm64e` (pointer authentication). Verify Cargo
  target `aarch64-apple-ios` produces `arm64e`-compatible code or add a separate target.
