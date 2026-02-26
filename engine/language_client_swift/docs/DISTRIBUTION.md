# Swift Package Distribution Plan

## Overview

BAML's Swift client needs to be installable via Swift Package Manager. SPM's
`.package(url:from:)` clones a Git repo and expects `Package.swift` at the **root**.
There is no subdirectory support, which means the main `boundaryml/baml` monorepo can't
serve as the SPM source directly.

The standard solution (used by Firebase, AWS SDK, gRPC-Swift) is a **mirror repo** whose
sole job is to hold a `Package.swift` pointing to the release XCFramework and a copy of the
Swift sources. CI auto-pushes to it on every BAML release.

---

## Repositories

| Repo | Purpose |
|------|---------|
| `boundaryml/baml` | Main monorepo — Rust, Go, Python, generators, etc. |
| `boundaryml/baml-swift` | SPM mirror — static linking (Milestone 1) |
| `boundaryml/baml-swift-dynamic` | SPM mirror — dynamic/lazy loading (Milestone 2) |

Users add the static package:
```swift
.package(url: "https://github.com/boundaryml/baml-swift.git", from: "0.219.0")
```

---

## Mirror Repo Structure

```
baml-swift/                          # repo root
├── Package.swift                    # binaryTarget pointing to GitHub release zip
├── Sources/
│   └── BamlSwift/                   # copy of engine/language_client_swift/Sources/BamlSwift/
│       ├── FFIBridge/
│       ├── Runtime/
│       ├── Serde/
│       ├── Proto/
│       └── Types/
└── README.md
```

`Package.swift` uses a remote `binaryTarget`:
```swift
.binaryTarget(
    name: "BamlCFFI",
    url: "https://github.com/boundaryml/baml/releases/download/0.219.0/BamlCFFI.xcframework.zip",
    checksum: "<spm-checksum>"
)
```

The `checksum` is the output of `swift package compute-checksum` (SHA-256 of the zip,
formatted as a lowercase hex string). It differs from the raw `sha256sum` output — SPM uses
its own checksum computation.

---

## Release Workflow

### Step 1 — Build and upload XCFramework (already automated)

`build-swift-release.reusable.yaml`:
1. Compiles all Rust targets.
2. Assembles `BamlCFFI.xcframework`.
3. Zips and computes both `sha256` and `spm_checksum`.
4. Uploads as GitHub Actions artifact.

`release.yml` downloads the artifact and uploads `BamlCFFI.xcframework.zip` +
`BamlCFFI.xcframework.zip.sha256` to the GitHub Release.

### Step 2 — Push to mirror repo (to be automated)

Add a new job to `build-swift-release.reusable.yaml` (runs after `publish-release` on tags):

```yaml
push-to-baml-swift:
  name: Push to baml-swift mirror repo
  needs: [test-macos, test-ios-simulator]
  runs-on: ubuntu-latest
  if: startsWith(github.ref, 'refs/tags/')

  steps:
    - uses: actions/checkout@v4
      with:
        path: baml

    - name: Clone baml-swift mirror
      run: |
        git clone https://x-access-token:${{ secrets.BAML_SWIFT_PUSH_TOKEN }}@github.com/boundaryml/baml-swift.git baml-swift

    - name: Sync Swift sources
      run: |
        rsync -av --delete \
          baml/engine/language_client_swift/Sources/BamlSwift/ \
          baml-swift/Sources/BamlSwift/

    - name: Download XCFramework artifact
      uses: actions/download-artifact@v4
      with:
        name: BamlCFFI-xcframework
        path: xcframework

    - name: Stamp Package.swift
      run: |
        VERSION="${{ github.ref_name }}"
        SPM_CHECKSUM=$(cat xcframework/BamlCFFI.xcframework.zip.sha256)
        bash baml/engine/language_client_swift/scripts/stamp-distribution-package.sh \
          "$VERSION" "$SPM_CHECKSUM"
        cp baml/engine/language_client_swift/Package.swift baml-swift/Package.swift

    - name: Commit and tag
      working-directory: baml-swift
      run: |
        git config user.name  "github-actions[bot]"
        git config user.email "github-actions[bot]@users.noreply.github.com"
        git add -A
        git commit -m "Release ${{ github.ref_name }}" || echo "Nothing to commit"
        git tag "${{ github.ref_name }}"
        git push origin main --tags
```

### Required secrets

| Secret | Description |
|--------|-------------|
| `OPENROUTER_API_KEY` | LLM key for integration tests |
| `BAML_SWIFT_PUSH_TOKEN` | GitHub PAT with `repo` scope for pushing to `baml-swift` |

Add both in **GitHub → Settings → Secrets and variables → Actions**.

---

## One-Time Setup: Create the Mirror Repo

1. Create `boundaryml/baml-swift` on GitHub (empty, public).
2. Initialize with a placeholder `README.md` and push an initial commit to `main`.
3. Create the `BAML_SWIFT_PUSH_TOKEN` PAT:
   - GitHub → Settings → Developer settings → Personal access tokens (classic)
   - Scopes: `repo` (full control of private repositories)
   - Add to `boundaryml/baml` repo secrets as `BAML_SWIFT_PUSH_TOKEN`.
4. Repeat for `boundaryml/baml-swift-dynamic` when Milestone 2 is ready.

---

## SPM Checksum vs SHA-256

These are two different things:

| | `shasum -a 256` | `swift package compute-checksum` |
|---|---|---|
| Algorithm | SHA-256 of the raw bytes | SHA-256 of the zip contents via SPM's own hasher |
| Format | lowercase hex string | lowercase hex string |
| Used for | `BamlCFFI.xcframework.zip.sha256` file (informational) | `Package.swift` `checksum:` field |

The `build-swift-release.reusable.yaml` job computes and exposes both as step outputs:
```yaml
SPM=$(swift package compute-checksum BamlCFFI.xcframework.zip)
echo "spm_checksum=$SPM" >> $GITHUB_OUTPUT
```

The `stamp-distribution-package.sh` script consumes `spm_checksum`.

---

## Versioning

Mirror repo tags must **exactly match** the main repo release tags (e.g. `0.219.0`).
SPM resolves `from: "0.219.0"` by fetching the tag `0.219.0` from `baml-swift`.

The BAML release process already tags the main repo with `X.Y.Z`; the mirror push job
re-tags the mirror repo with the same value.

---

## Local Development

The mirror repo is for distribution only — it has no Rust code and no local build script.
For local development:

- **macOS**: use `engine/language_client_swift/Package.swift` (systemLibrary) +
  `BAML_LIBRARY_PATH=.../libbaml_cffi.dylib swift test`
- **iOS simulator**: use `integ-tests/swift-ios/Package.swift` (local binaryTarget via
  symlink to the built XCFramework)

Neither of these involves the mirror repo.

---

## Checklist Before First Release

- [ ] `boundaryml/baml-swift` repo created and initialized
- [ ] `BAML_SWIFT_PUSH_TOKEN` secret added to `boundaryml/baml`
- [ ] `OPENROUTER_API_KEY` secret added to `boundaryml/baml`
- [ ] `build-swift-release.reusable.yaml` `push-to-baml-swift` job added and tested on a
      `test-release/X.Y.Z` tag
- [ ] `Package.distribution.swift` placeholder values confirmed correct
- [ ] Integration tests pass on both macOS and iOS simulator
- [ ] `baml-swift` repo README updated with installation instructions
- [ ] `baml-cli generate` tested end-to-end with `output_type swift`
