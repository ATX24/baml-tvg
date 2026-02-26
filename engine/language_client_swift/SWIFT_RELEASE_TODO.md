# Swift Package Distribution — Manual Steps

This file documents what needs to be done by a human before the Swift package
is ready for public distribution. Everything that could be automated has been.

---

## 1. Update `Package.swift` for production XCFramework

Right now `Package.swift` uses a `.systemLibrary` target (local development only).
For production, switch the `BamlCFFI` target to a `.binaryTarget` pointing to the
hosted XCFramework zip.

**Change this:**
```swift
.systemLibrary(
    name: "BamlCFFI",
    path: "include",
    pkgConfig: nil,
    providers: []
),
```

**To this:**
```swift
.binaryTarget(
    name: "BamlCFFI",
    url: "https://github.com/BoundaryML/baml/releases/download/<VERSION>/BamlCFFI.xcframework.zip",
    checksum: "<SHA256-from-BamlCFFI.xcframework.zip.sha256>"
),
```

The CI workflow (`build-swift-release.reusable.yaml`) automates this substitution
at release time using sed on placeholder strings — but the initial `Package.swift`
needs the placeholders set up (see step below).

**Action:** Decide whether to keep the current `systemLibrary` default for local dev
and have CI swap it for releases, or maintain two separate `Package.swift` files.
The recommended approach: add a `Package.release.swift` that CI copies over.


## 2. Host the XCFramework on GitHub Releases

The XCFramework zip (currently `BamlCFFI.xcframework.zip`, 112 MB) must be attached
to a GitHub Release so Swift Package Manager can download it.

Steps:
1. Tag a release (e.g., `swift-0.1.0`) on the BAML repo.
2. Upload `BamlCFFI.xcframework.zip` as a release asset.
3. Copy the SHA256 from `BamlCFFI.xcframework.zip.sha256`.
4. Update `Package.swift` `url:` and `checksum:` fields.

The CI workflow (`build-swift-release.reusable.yaml` → `publish-package` job)
handles steps 2–4 automatically when you push a tag.


## 3. Wire the CI workflow into `release.yml`

Add the Swift build job to `.github/workflows/release.yml` so it runs on every release:

```yaml
# In release.yml, add:
build-swift:
  uses: ./.github/workflows/build-swift-release.reusable.yaml
  secrets: inherit
```

Also add `OPENROUTER_API_KEY` to the repo's GitHub Secrets if you want the
integration tests to run in CI.


## 4. Add `baml generate --output-type swift` to the CLI

The published `@boundaryml/baml` CLI (v0.219.0) does not yet know about the `swift`
output type — only the local Rust codebase does. To let users run `baml generate`
to get Swift clients, you need to:

1. Build the `baml-cli` binary from source and publish it.
2. Or publish a new npm `@boundaryml/baml` version that includes the Swift generator.

Until then, users must hand-write or copy their `baml_client/` from
`integ-tests/swift/baml_client/` as a reference.


## 5. Publish the Swift package to a public SPM-discoverable location

Options:
- **Same repo** (`BoundaryML/baml`): Set `Package.swift` at the repo root or in
  `engine/language_client_swift/`. Users add:
  ```swift
  .package(url: "https://github.com/BoundaryML/baml", from: "0.1.0")
  ```
- **Separate repo** (`BoundaryML/baml-swift`): Cleaner versioning, but requires
  keeping the two repos in sync.


## 6. Consider a SPM plugin for code generation

For a great developer experience, add an SPM build plugin that runs `baml generate`
as a build phase. This would regenerate the `baml_client/` Swift files automatically
whenever the `.baml` source files change.

Reference: https://developer.apple.com/documentation/packagedescription/commandplugin


## 7. Verify iOS simulator and device builds

The XCFramework includes three slices:
- `ios-arm64` (device)
- `ios-arm64_x86_64-simulator` (simulator)
- `macos-arm64_x86_64` (macOS)

Before publishing, verify that an iOS app can import `BamlSwift` and call a generated
function on both device and simulator. The CI only tests macOS.


## Summary of files already in place

| File | Status |
|------|--------|
| `engine/language_client_swift/` | ✅ BamlSwift Swift Package |
| `engine/language_client_swift/BamlCFFI.xcframework` | ✅ Built locally |
| `engine/language_client_swift/BamlCFFI.xcframework.zip` | ✅ 112 MB |
| `engine/language_client_swift/BamlCFFI.xcframework.zip.sha256` | ✅ SHA256 computed |
| `engine/language_client_swift/scripts/build-xcframework.sh` | ✅ Reproducible build |
| `.github/workflows/build-swift-release.reusable.yaml` | ✅ CI workflow (needs wiring) |
| `engine/generators/languages/swift/` | ✅ Rust code generator |
| `integ-tests/swift/` | ✅ Integration test package |
| `integ-tests/swift/baml_client/` | ✅ Hand-written generated client |
