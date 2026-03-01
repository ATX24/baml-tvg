# BAML Swift Client — Build Report

---

## Part 1: What We Built

### Overview

A complete Swift language client for BAML targeting both macOS and iOS. The client exposes
BAML functions as native Swift `async/await` APIs with full type safety, streaming support,
and protobuf serialisation over a C FFI boundary. It ships in two linking modes:

| Mode | Platform | Mechanism |
|------|----------|-----------|
| Dynamic (`dlopen`) | macOS | `libbaml_cffi.dylib` loaded at runtime via `BAML_LIBRARY_PATH` or auto-download |
| Static (XCFramework) | iOS + macOS | `BamlCFFI.xcframework` linked at build time via SPM `binaryTarget` |

---

### 1. Swift Package — `engine/language_client_swift`

The core library package. Contains all runtime, FFI, serde, and proto code.

```
engine/language_client_swift/
├── Package.swift                    # Local dev (systemLibrary target)
├── Package.distribution.swift      # Distribution template (binaryTarget URL)
├── Sources/BamlSwift/
│   ├── FFIBridge/
│   │   ├── FFIFunctions.swift       # C call wrappers; #if os(macOS) / #else branches
│   │   ├── DynamicLoader.swift      # macOS dlopen / dlsym symbol resolution
│   │   ├── Buffer.swift             # FFIBuffer wrapping C Buffer struct
│   │   └── MacOSDownloader.swift    # Downloads dylib from GitHub releases on macOS
│   ├── Runtime/
│   │   ├── BamlRuntime.swift        # Public runtime class; async callFunction / stream
│   │   └── Callbacks.swift          # Thread-safe callback registry (callId → continuation)
│   ├── Serde/
│   │   ├── Encode.swift             # Swift → protobuf HostValue; public encodeFunctionArgs
│   │   └── Decode.swift             # protobuf CFFIValueHolder → Swift; public decodeResult<T>
│   ├── Proto/baml/cffi/v1/
│   │   ├── baml_inbound.pb.swift    # HostValue, HostFunctionArguments, etc.
│   │   ├── baml_outbound.pb.swift   # CFFIValueHolder, InvocationResponse, etc.
│   │   ├── baml_object.pb.swift
│   │   └── baml_object_methods.pb.swift
│   └── Types/
│       ├── BamlError.swift          # BamlError enum
│       ├── Checked.swift            # Checked<T> wrapper
│       └── StreamState.swift        # StreamState<T>: pending / started / done
├── include/
│   ├── baml_cffi_generated.h        # C header (cbindgen output)
│   └── module.modulemap             # Clang module map (no `link` directive)
├── scripts/
│   ├── build-xcframework.sh         # Compiles all 5 Rust targets → fat libs → XCFramework → zip
│   ├── run-tests.sh                 # Runs macOS tests with BAML_LIBRARY_PATH
│   └── stamp-distribution-package.sh # Substitutes version/checksum into Package.distribution.swift
└── docs/
    ├── IMPLEMENTATION_PLAN.md
    ├── REPORT.md                    # This file
    ├── distribution.md              # Plan for baml-swift mirror repo + CI
    └── dynamic.md                   # Plan for Milestone 2 dynamic iOS loading
```

#### Key design decisions

**Public API surface** — `BamlDecoder` and `BamlEncoder` are `public` enums, but all
methods that return internal proto types stay `internal`. Only these are public:
- `BamlDecoder.decodeResult<T: Decodable>(_ data: Data) throws -> T` — full pipeline from raw bytes to typed T
- `BamlDecoder.decodeStreamChunk<T: Sendable & Decodable>(_ data: Data) throws -> StreamState<T>` — for streaming
- `BamlDecoder.convert<T: Decodable>(_ any: Any?) throws -> T` — `Any?` → T via JSON roundtrip
- `BamlEncoder.encodeFunctionArgs(kwargs:envVars:) throws -> Data` — public overload without clientRegistry

**`decodeResult` implementation** — Uses a JSON roundtrip via `_BamlWrapper<T>` to convert
`Any?` (untyped decoded value) into any `Decodable` type. Handles plain types (String,
Int64, Double, Bool), enums with `String` rawValue, and `Codable` structs for class types.

**`module.modulemap` — no `link` directive** — The module map intentionally omits a `link`
directive. On macOS the library is loaded at runtime via `dlopen`; on iOS SPM's
`binaryTarget` handles linking. A `link` directive would cause double-linking on iOS.

**Callbacks** — The Rust CFFI delivers async results via C function pointer callbacks
(`CallbackFn`, `OnTickCallbackFn`). Swift registers global `@_cdecl` functions once at
startup. A thread-safe `CallbackRegistry` actor maps `callId → CheckedContinuation` for
single calls and `callId → AsyncThrowingStream.Continuation` for streaming calls.

**env vars** — API keys (e.g. `OPENROUTER_API_KEY`) are passed **per call** via
`BamlEncoder.encodeFunctionArgs(envVars:)`, not in the `BamlRuntime` constructor. The
constructor `envVars` are for BAML configuration, not LLM client resolution.

---

### 2. XCFramework — `BamlCFFI.xcframework`

A pre-compiled multi-platform static library containing the entire Rust CFFI stack.

| Slice | Targets |
|-------|---------|
| `ios-arm64` | Physical iPhone / iPad |
| `ios-arm64_x86_64-simulator` | iOS Simulator (Apple Silicon + Intel, fat binary) |
| `macos-arm64_x86_64` | macOS (Apple Silicon + Intel, fat binary) |

**Build**: `scripts/build-xcframework.sh` compiles 5 Cargo targets in release mode
(`aarch64-apple-ios`, `aarch64-apple-ios-sim`, `x86_64-apple-ios`, `aarch64-apple-darwin`,
`x86_64-apple-darwin`), creates fat binaries with `lipo`, and assembles with
`xcodebuild -create-xcframework`.

**Artifacts** (at `engine/language_client_swift/`):
- `BamlCFFI.xcframework` — unzipped, used locally
- `BamlCFFI.xcframework.zip` — 112 MB, uploaded to GitHub Releases for SPM
- `BamlCFFI.xcframework.zip.sha256` — SHA-256 for verification

**iOS compile fix** — The `gcp_auth` crate (Vertex AI auth) does not compile for iOS.
Gated behind `cfg(not(target_os = "ios"))` in `engine/baml-runtime/Cargo.toml` with an
iOS stub at `engine/baml-runtime/src/internal/llm_client/primitive/vertex/ios_auth.rs`.

---

### 3. Swift Code Generator — `engine/generators/languages/swift`

A Rust crate that implements `LanguageFeatures` for Swift, wired into `baml-cli generate`
via `output_type swift` in a `.baml` generator block.

```
engine/generators/languages/swift/
├── src/
│   ├── lib.rs                  # SwiftLanguageFeatures — generates 7 output files
│   ├── functions.rs            # Askama templates: BamlRuntime.swift, BamlFunctions.swift, BamlSourceMap.swift
│   ├── generated_types.rs      # Renders structs, enums, unions via type templates
│   ├── type.rs                 # TypeSwift: BAML → Swift type mapping + is_stream_state()
│   ├── utils.rs
│   └── ir_to_swift/
│       ├── classes.rs          # IR Class → Swift struct (Codable, Sendable)
│       ├── enums.rs            # IR Enum → Swift enum (String, Codable, CaseIterable)
│       ├── functions.rs        # IR Function → FunctionSwift (args, return_type, stream_return_type)
│       ├── unions.rs           # IR Union → Swift enum with associated values
│       └── type_aliases.rs
└── src/_templates/
    ├── function.swift.j2       # Single typed async function
    ├── function.stream.swift.j2 # Single streaming function (AsyncThrowingStream)
    ├── class.swift.j2          # Struct template
    ├── enums.swift.j2          # Enum template
    └── unions.swift.j2         # Union enum template
```

**Generated output** (7 files per project):

| File | Contents |
|------|----------|
| `BamlSourceMap.swift` | Embedded `.baml` file map as `[String: String]` |
| `BamlRuntime.swift` | Lazy `bamlClient: BamlRuntime` global |
| `BamlFunctions.swift` | Typed `async throws` wrappers + `processEnv()` helper |
| `BamlFunctionsStream.swift` | `AsyncThrowingStream` wrappers |
| `BamlTypes.swift` | All `Codable, Sendable` structs |
| `BamlEnums.swift` | All `String, Codable, CaseIterable` enums |
| `BamlUnions.swift` | Union enums with associated values |

**Type mapping** (BAML → Swift):

| BAML | Swift |
|------|-------|
| `string` | `String` |
| `int` | `Int64` |
| `float` | `Double` |
| `bool` | `Bool` |
| `null` / optional | `Optional<T>` |
| `T[]` | `[T]` |
| `map<string, T>` | `[String: T]` |
| `class Foo` | `struct Foo: Codable, Sendable` |
| `enum Bar` | `enum Bar: String, Codable, CaseIterable` |
| `Foo \| Bar` | `enum FooOrBar` with associated values |
| streaming return | `AsyncThrowingStream<StreamState<T>, Error>` |

**`processEnv()` helper** — Generated into `BamlFunctions.swift`. Normalises
`TEST_RUNNER_*` env var prefixes that `xcodebuild` may or may not strip, ensuring
`OPENROUTER_API_KEY` is always found regardless of how the test runner is invoked.

---

### 4. macOS Integration Tests — `integ-tests/swift`

Tests the dynamic linking path (macOS + `dlopen`).

```
integ-tests/swift/
├── Package.swift                    # Depends on engine/language_client_swift via local path
├── baml_src/
│   ├── clients.baml                 # OpenRouter client (stepfun/step-3.5-flash:free)
│   ├── functions.baml               # SayHello, ClassifySentiment, ExtractGreeting, ExtractResume
│   └── generators.baml              # output_type swift (not embedded in runtime file map)
├── baml_client/                     # Hand-written generated client (mirrors generator output)
│   ├── BamlClient.swift             # bamlClient lazy global
│   ├── BamlFunctions.swift          # Typed async functions + processEnv()
│   ├── BamlFunctionsStream.swift    # Streaming variants
│   ├── BamlTypes.swift              # Resume, NamedGreeting structs
│   └── BamlEnums.swift              # Sentiment enum
└── Tests/BamlIntegTests/
    └── BamlIntegTests.swift         # 6 tests (skips gracefully if OPENROUTER_API_KEY unset)
```

**Tests** (all call the live LLM via OpenRouter):

| Test | Function | Return type |
|------|----------|-------------|
| `testSayHello` | `SayHello(name:)` | `String` |
| `testClassifySentimentPositive` | `ClassifySentiment(text:)` | `Sentiment` (enum) |
| `testClassifySentimentNegative` | `ClassifySentiment(text:)` | `Sentiment` (enum) |
| `testExtractGreeting` | `ExtractGreeting(text:)` | `NamedGreeting` (struct) |
| `testExtractResume` | `ExtractResume(text:)` | `Resume` (struct with array) |
| `testSayHelloStream` | `SayHelloStream(name:)` | `AsyncThrowingStream<String, Error>` |

**Run**:
```bash
OPENROUTER_API_KEY=<key> \
BAML_LIBRARY_PATH=engine/target/aarch64-apple-darwin/release/libbaml_cffi.dylib \
swift test
```

---

### 5. iOS Simulator Integration Tests — `integ-tests/swift-ios`

Tests the static XCFramework linking path (iOS).

```
integ-tests/swift-ios/
├── Package.swift                    # iOS-only (.iOS(.v15)); binaryTarget via symlink
├── BamlCFFI.xcframework             # Symlink → engine/language_client_swift/BamlCFFI.xcframework
├── Sources/
│   ├── BamlSwift/                   # Symlink → engine/language_client_swift/Sources/BamlSwift
│   └── BamlClient/                  # Symlink → integ-tests/swift/baml_client
└── Tests/BamlIOSIntegTests/
    └── BamlIOSIntegTests.swift      # 7 tests including testRuntimeInitializes smoke test
```

**Tests** (same 6 LLM tests as macOS, plus one extra):

| Test | Purpose |
|------|---------|
| `testRuntimeInitializes` | Smoke test: XCFramework links and runtime initialises without crashing |
| `testSayHello` | String return |
| `testClassifySentimentPositive/Negative` | Enum return |
| `testExtractGreeting` | Struct return |
| `testExtractResume` | Struct with array return |
| `testSayHelloStream` | Streaming |

**Run** (requires XCFramework built first):
```bash
# Build
xcodebuild build-for-testing \
  -scheme BamlIOSIntegTests-Package \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5'

# Inject API key into .xctestrun manifest
XCTESTRUN=$(find ~/Library/Developer/Xcode/DerivedData -name "*.xctestrun" -path "*/swift-ios*" | tail -1)
/usr/libexec/PlistBuddy \
  -c "Add :TestConfigurations:0:TestTargets:0:TestingEnvironmentVariables:OPENROUTER_API_KEY string $OPENROUTER_API_KEY" \
  "$XCTESTRUN"

# Run
xcodebuild test-without-building \
  -xctestrun "$XCTESTRUN" \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5'
```

---

### 6. CI / CD — `.github/workflows`

**`build-swift-release.reusable.yaml`** — 3 jobs:

| Job | Runner | What it does |
|-----|--------|--------------|
| `build-xcframework` | `macos-14` | Compiles all Rust targets, assembles XCFramework, zips, computes checksums, uploads as artifact |
| `test-macos` | `macos-14` | Builds `aarch64-apple-darwin` dylib, runs `swift test` with `BAML_LIBRARY_PATH` |
| `test-ios-simulator` | `macos-14` | Downloads XCFramework artifact, unzips, `build-for-testing` + `PlistBuddy` inject + `test-without-building` |

**`release.yml`** — calls the reusable workflow as `build-swift-xcframework` with
`secrets: inherit`, adds it to the `all-builds` gate, and downloads + uploads
`BamlCFFI.xcframework.zip` / `.sha256` to the GitHub Release.

**Required secret**: `OPENROUTER_API_KEY` — add in GitHub → Settings → Secrets and
variables → Actions.

---

### 7. Distribution — `Package.distribution.swift` + `scripts/stamp-distribution-package.sh`

Template and tooling for the future `boundaryml/baml-swift` SPM mirror repo.

`Package.distribution.swift` contains:
```swift
.binaryTarget(
    name: "BamlCFFI",
    url: "https://github.com/boundaryml/baml/releases/download/BAML_VERSION/BamlCFFI.xcframework.zip",
    checksum: "BAML_SPM_CHECKSUM"
)
```

`stamp-distribution-package.sh <version> <spm_checksum>` substitutes both placeholders
and writes the stamped result to `Package.swift`. See `docs/distribution.md` for the full
mirror repo push workflow.

---

## Part 2: Bugs & Fixes

This section records every significant bug encountered and how it was resolved.

---

### 1. `BamlDecoder` / `BamlEncoder` visibility — internal proto types leaked into public API

**Bug**
After making `BamlDecoder` and `BamlEncoder` `public`, the Swift compiler rejected the module
because methods like `decodeResponse`, `decode`, `encodeClass`, `encodeEnum`, and `encodeValue`
return or accept internal proto types (`Baml_Cffi_V1_CFFIValueHolder`,
`Baml_Cffi_V1_HostValue`, etc.).  Public methods cannot expose internal types.

**Fix**
Kept all proto-type methods `internal`.  Added a separate layer of public helpers that only
use standard types (`Data`, `Any?`, generic `T: Decodable`):
- `BamlDecoder.decodeResult<T: Decodable>(_ data: Data) throws -> T`
- `BamlDecoder.decodeStreamChunk<T: Sendable & Decodable>(_ data: Data) throws -> StreamState<T>`
- `BamlDecoder.convert<T: Decodable>(_ any: Any?) throws -> T`
- `BamlEncoder.encodeFunctionArgs(kwargs:envVars:) -> Data` (public overload, no `clientRegistry`)

The `clientRegistry` parameter uses an internal proto type, so it lives in an `internal`
overload; the public overload forwards to it with `clientRegistry: nil`.

---

### 2. Nested generic struct inside generic function

**Bug**
Inside `BamlDecoder.convert<T>`, defining `struct Wrapper<U: Decodable>: Decodable { let _v: U }`
caused a compiler error: Swift does not allow a generic type to be nested inside a generic
function.

**Fix**
Moved the wrapper to file scope as a private type:
```swift
private struct _BamlWrapper<T: Decodable>: Decodable { let _v: T }
```
`convert<T>` uses `_BamlWrapper<T>` directly.

---

### 3. SPM package identity mismatch — "unknown package 'BamlSwift'"

**Bug**
`integ-tests/swift/Package.swift` referenced the engine package as:
```swift
.product(name: "BamlSwift", package: "BamlSwift")
```
SPM resolved this with an "unknown package 'BamlSwift'" error.

**Fix**
For path-based local packages, the `package:` label must match the **directory name**, not
the `name:` field inside `Package.swift`.  The engine package lives at
`../../engine/language_client_swift`, so the correct reference is:
```swift
.product(name: "BamlSwift", package: "language_client_swift")
```

---

### 4. `generators.baml` embedded in the BAML runtime source map

**Bug**
`BamlClient.swift` initially embedded all `.baml` files including `generators.baml`, which
contains `output_type swift`.  The BAML runtime rejected this at startup with:
```
output_type swift not found
```
because `swift` is not a known output type from the runtime's perspective (older dylib build).

**Fix**
Removed `generators.baml` from the embedded source file map.  Only `clients.baml` and
`functions.baml` are needed by the runtime.

---

### 5. Swift raw string escaping conflict with BAML prompt syntax

**Bug**
`functions.baml` uses BAML's `#"..."#` syntax for prompts.  When this content was embedded
in a Swift `#"""..."""#` raw string literal, the Swift parser treated `"#` as the string
terminator, producing a compile error.

**Fix**
Used a double-hash raw string delimiter `##"""..."""##` for the `functions.baml` value so
that a lone `"#` inside the string is no longer interpreted as a terminator.

---

### 6. `export` syntax errors — environment variable not set

**Bug**
Running `echo OPENROUTER_API_KEY=sk-or-...` only prints the string; it does not set the
variable.  Similarly, `export OPENROUTER_API_KEY = sk-or-...` (spaces around `=`) silently
fails to set the variable in most shells.

**Fix**
Correct syntax: `export OPENROUTER_API_KEY=sk-or-...` (no spaces, `export` not `echo`).

---

### 7. `Int` vs `UInt` / `uintptr_t` type mismatch on iOS static builds

**Bug**
`FFIFunctions.swift` has `#if os(macOS)` / `#else` branches.  The macOS branch calls
function pointers typed in Swift (using `Int` for length), while the iOS `#else` branch
calls C symbols directly from the XCFramework.  The C header uses `uintptr_t` for buffer
lengths, which Swift maps to `UInt`.  `Data.count` returns `Int`, so the iOS branch produced:
```
error: cannot convert value of type 'Int' to expected argument type 'UInt'
```
in all six call sites: `callFunction`, `callFunctionStream`, `callFunctionParse`,
`buildRequest`, `callObjectConstructor`, `callObjectMethod`.

**Fix**
Explicit cast at every iOS call site:
```swift
return call_function_from_c(runtime, cName, ptr, UInt(encodedArgs.count), callId)
```

---

### 8. `xcodebuild -testEnvironmentVariables` not available / iOS simulator env var injection

**Bug**
Multiple attempts to inject `OPENROUTER_API_KEY` into the iOS simulator test process all
failed:
- `-testEnvironmentVariables OPENROUTER_API_KEY=...` → `xcodebuild: error: invalid option`
  (not available in Xcode 16.4)
- `TEST_RUNNER_OPENROUTER_API_KEY=...` as a build setting override → silently swallowed;
  the `TEST_RUNNER_` prefix stripping that Xcode performs via the GUI scheme does **not**
  trigger when set from the command line.
- `xcrun simctl setenv` → `Unrecognized subcommand: setenv` (not available in this
  CoreSimulator version)

As a result, tests passed in <0.01 s (the `guard !shouldSkip` early-return fired), with no
actual LLM calls made.

**Fix**
Two-step build + inject pattern:

```bash
# 1. Build and produce a .xctestrun manifest
xcodebuild build-for-testing \
  -scheme BamlIOSIntegTests-Package \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'

# 2. Inject the env var directly into the manifest
XCTESTRUN=$(find ~/Library/Developer/Xcode/DerivedData -name "*.xctestrun" \
              -path "*/swift-ios*" | tail -1)
/usr/libexec/PlistBuddy \
  -c "Add :TestConfigurations:0:TestTargets:0:TestingEnvironmentVariables:OPENROUTER_API_KEY string $OPENROUTER_API_KEY" \
  "$XCTESTRUN"

# 3. Run without rebuilding
xcodebuild test-without-building \
  -xctestrun "$XCTESTRUN" \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'
```

`PlistBuddy` writes into `TestingEnvironmentVariables` inside the `.xctestrun` plist, which
is the correct path that Xcode reads when launching the test runner inside the simulator.

Additionally, `BamlFunctions.swift` was updated with a `processEnv()` helper that normalises
`TEST_RUNNER_*` prefixed variables as a belt-and-suspenders fallback for future Xcode
versions where the stripping may start working:
```swift
func processEnv() -> [String: String] {
    var env = ProcessInfo.processInfo.environment
    for (key, value) in env where key.hasPrefix("TEST_RUNNER_") {
        let stripped = String(key.dropFirst("TEST_RUNNER_".count))
        if env[stripped] == nil { env[stripped] = value }
    }
    return env
}
```

---

### 9. `xcodebuild` multiline command parsing in zsh

**Bug**
Splitting a long `xcodebuild` command across multiple lines with backslash continuation
caused zsh to parse subsequent lines as separate commands:
```
zsh: command not found: -scheme
```

**Fix**
Put the entire `xcodebuild` invocation on a single line, or use a shell here-string / array
variable to build the argument list before calling the command.

---

### 10. Wrong xcodebuild scheme name for SPM packages

**Bug**
Using `-scheme BamlIOSIntegTests` produced:
```
xcodebuild: error: The project 'BamlIOSIntegTests' does not contain a scheme named 'BamlIOSIntegTests'.
```

**Fix**
For Swift Package Manager packages, `xcodebuild` auto-generates a scheme named
`<PackageName>-Package`.  Discovered via:
```bash
xcodebuild -list
```
Correct scheme: `BamlIOSIntegTests-Package`.

---

### 11. iOS simulator not found — iPhone 15 vs iPhone 16

**Bug**
`-destination 'platform=iOS Simulator,name=iPhone 15,OS=latest'` failed because no iPhone 15
simulator was installed on the build machine.

**Fix**
Used `xcrun simctl list devices` to find installed simulators and updated the destination to
`name=iPhone 16,OS=18.5`.

---

### 12. `processEnv()` is `private` — not visible across Swift source files

**Bug**
`processEnv()` was declared `private` in `BamlFunctions.swift`.  In Swift, `private` is
file-scoped, so `BamlFunctionsStream.swift` (a different file in the same module) could not
see it:
```
error: cannot find 'processEnv' in scope
```

**Fix**
Removed the `private` access modifier, making the function `internal` (the default) so it
is accessible across all files in the `BamlClient` module.

---

### 13. iOS vertex/GCP auth crate — compile error on iOS targets

**Bug**
The `gcp_auth` crate was unconditionally included in `baml-runtime`, and it does not compile
for iOS targets (`aarch64-apple-ios`, `aarch64-apple-ios-sim`).

**Fix**
Gated the dependency behind a `cfg` predicate in `engine/baml-runtime/Cargo.toml`:
```toml
[target.'cfg(all(not(target_arch = "wasm32"), not(target_os = "ios")))'.dependencies]
gcp_auth = "..."
```
Added an iOS stub module `engine/baml-runtime/src/internal/llm_client/primitive/vertex/ios_auth.rs`
that returns a compile-time-safe placeholder.
