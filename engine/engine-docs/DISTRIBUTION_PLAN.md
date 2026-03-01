# Swift Package Distribution Plan

## Overview

BAML's Swift client needs to be installable via Swift Package Manager. SPM's
`.package(url:from:)` clones a Git repo and expects `Package.swift` at the **root**.
There is no subdirectory support, which means the main `atx24/baml-tvg` monorepo can't
serve as the SPM source directly.

We use the same strategy as **Apollo GraphQL iOS**: a **git subtree** to push
`engine/language_client_swift/` to a standalone distribution repo on every release.
All development happens in the monorepo. The distribution repo (`baml-swift`) is a
read-only artifact that CI keeps in sync — developers never touch it directly.

The key advantage over a plain rsync mirror: `git subtree split` rewrites the actual
commit history from the monorepo, so `baml-swift` has a real, meaningful git log rather
than a single "Release X.Y.Z" squash commit per version.

---

## Repositories

| Repo | Purpose |
|------|---------|
| `atx24/baml-tvg` | Main monorepo — Rust, Go, Python, generators, etc. |
| `atx24/baml-swift-prototype` | SPM distribution repo — populated via git subtree |

Users add the package:
```swift
.package(url: "https://github.com/atx24/baml-swift-prototype.git", from: "0.219.0")
```

---

## Distribution Repo Structure

```
baml-swift/                          # repo root (= engine/language_client_swift/ in baml)
├── Package.swift                    # binaryTarget pointing to GitHub release zip
├── Sources/
│   └── BamlSwift/                   # Swift FFI wrapper source
│       ├── FFIBridge/
│       ├── Runtime/
│       ├── Serde/
│       ├── Proto/
│       └── Types/
├── include/                         # C header + module.modulemap (for systemLibrary)
└── README.md
```

`Package.swift` in the distribution repo uses a remote `binaryTarget`:
```swift
.binaryTarget(
    name: "BamlCFFI",
    url: "https://github.com/atx24/baml-tvg/releases/download/0.219.0/BamlCFFI.xcframework.zip",
    checksum: "<spm-checksum>"
)
```

This is different from the development `Package.swift` (which uses `systemLibrary`).
The stamp script swaps it out before pushing to `baml-swift`.

The `checksum` is the output of `swift package compute-checksum` (SHA-256 of the zip
formatted as a lowercase hex string). It differs from raw `sha256sum` — SPM uses its
own checksum computation.

---

## How Git Subtree Works

`git subtree split` walks the full commit history of the monorepo, finds every commit
that touched `engine/language_client_swift/`, and rewrites those commits as if that
directory were the repo root. The result is a synthetic branch whose history contains
only Swift-relevant commits.

```
atx24/baml-tvg (monorepo)           atx24/baml-swift-prototype
─────────────────────────            ──────────────────────────
  commit: "add Rust feature"    →    (skipped — no Swift changes)
  commit: "fix BamlDecoder"     →    commit: "fix BamlDecoder"
  commit: "update CI"           →    (skipped — no Swift changes)
  commit: "add streaming"       →    commit: "add streaming"
```

The `--rejoin` flag checkpoints the split so subsequent runs don't re-scan the entire
history — only new commits are processed.

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

### Step 2 — Push to baml-swift via git subtree

Add a new job to `build-swift-release.reusable.yaml` (runs after `publish-release` on tags):

```yaml
push-to-baml-swift:
  name: Push to baml-swift via git subtree
  needs: [test-macos, test-ios-simulator, publish-release]
  runs-on: ubuntu-latest
  if: startsWith(github.ref, 'refs/tags/')

  steps:
    - uses: actions/checkout@v4
      with:
        fetch-depth: 0  # full history required for git subtree split

    - name: Configure git
      run: |
        git config user.name  "github-actions[bot]"
        git config user.email "github-actions[bot]@users.noreply.github.com"

    - name: Download XCFramework artifact
      uses: actions/download-artifact@v4
      with:
        name: BamlCFFI-xcframework
        path: xcframework

    - name: Stamp distribution Package.swift
      run: |
        VERSION="${{ github.ref_name }}"
        SPM_CHECKSUM=$(cat xcframework/BamlCFFI.xcframework.zip.sha256)
        bash engine/language_client_swift/scripts/stamp-distribution-package.sh \
          "$VERSION" "$SPM_CHECKSUM"
        # Commit the stamped Package.swift into the monorepo temporarily
        # (git subtree split will include this commit in the distribution branch)
        git add engine/language_client_swift/Package.swift
        git commit -m "chore: stamp Package.swift for release $VERSION"

    - name: Split subtree and push to baml-swift
      env:
        BAML_SWIFT_PUSH_TOKEN: ${{ secrets.BAML_SWIFT_PUSH_TOKEN }}
      run: |
        VERSION="${{ github.ref_name }}"
        REMOTE="https://x-access-token:${BAML_SWIFT_PUSH_TOKEN}@github.com/atx24/baml-swift-prototype.git"

        # Split the subtree — extracts only commits touching engine/language_client_swift/
        # --rejoin creates a merge commit checkpoint so future splits are fast
        git subtree split \
          --prefix engine/language_client_swift \
          --rejoin \
          -b swift-dist-branch

        # Push the split branch to baml-swift main
        git push "$REMOTE" swift-dist-branch:main

        # Tag the release on baml-swift
        git push "$REMOTE" "swift-dist-branch:refs/tags/$VERSION"

    - name: Restore development Package.swift
      run: |
        # Revert the stamp commit so the monorepo Package.swift stays as systemLibrary
        git revert HEAD --no-edit
        git push origin main
```

### Required secrets

| Secret | Description |
|--------|-------------|
| `OPENROUTER_API_KEY` | LLM key for integration tests |
| `BAML_SWIFT_PUSH_TOKEN` | GitHub PAT with `repo` scope for pushing to `baml-swift` |

Add both in **GitHub → Settings → Secrets and variables → Actions**.

---

## One-Time Setup

### 1. Register the subtree remote locally (for manual operations)

```bash
git remote add baml-swift https://github.com/atx24/baml-swift-prototype.git
```

### 2. Initial push to create the baml-swift repo

On first release, bootstrap `baml-swift` from scratch:

```bash
# Full history required
git fetch --unshallow 2>/dev/null || true

# Split and push
git subtree push \
  --prefix engine/language_client_swift \
  --rejoin \
  baml-swift main
```

### 3. Create the baml-swift repo on GitHub

1. Create `atx24/baml-swift-prototype` on GitHub (empty, public).
2. Do **not** initialize with a README — let the first subtree push populate it.
3. Create `BAML_SWIFT_PUSH_TOKEN` PAT:
   - GitHub → Settings → Developer settings → Personal access tokens (classic)
   - Scopes: `repo` (full control)
   - Add to `atx24/baml-tvg` repo secrets as `BAML_SWIFT_PUSH_TOKEN`.

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

`baml-swift` tags must **exactly match** the main repo release tags (e.g. `0.219.0`).
SPM resolves `from: "0.219.0"` by fetching the tag `0.219.0` from `baml-swift`.

The CI job tags the split branch with the same `${{ github.ref_name }}` as the main release.

---

## Local Development

The distribution repo is never used during local development.

- **macOS**: `engine/language_client_swift/Package.swift` (systemLibrary) +
  `BAML_LIBRARY_PATH=.../libbaml_cffi.dylib swift test`
- **iOS demo**: open `engine/language_client_swift/docs/demos/ios/Scribe.xcodeproj`
  (links XCFramework directly, local package reference to `engine/language_client_swift`)

---

## Checklist Before First Release

- [ ] `atx24/baml-swift-prototype` repo created (empty, no initial commit)
- [ ] `BAML_SWIFT_PUSH_TOKEN` secret added to `atx24/baml-tvg`
- [ ] `OPENROUTER_API_KEY` secret added to `atx24/baml-tvg`
