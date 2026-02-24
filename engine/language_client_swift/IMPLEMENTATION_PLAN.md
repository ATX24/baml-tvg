
# BAML Swift Language Client — Implementation Plan

## Overview

This document describes how to build a Swift language client for BAML targeting **iOS** (and macOS). The goal is to enable Swift developers to call BAML functions from Swift code via the existing `baml_cffi` layer, with generated types and full protobuf serialization — mirroring the existing Go language client architecture.

The critical challenge: **`dlopen` behaves differently on iOS than on desktop platforms**. While `dlopen` *does* exist on iOS, Apple requires all dynamic libraries to be bundled within the app at submission time. You cannot download or side-load dylibs at runtime. This means we need a fundamentally different distribution and linking strategy than what the Go client uses (downloading `.dylib`/`.so` from GitHub releases at runtime).

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [iOS Dynamic Library Strategy](#2-ios-dynamic-library-strategy)
3. [Phase 1: XCFramework Build Pipeline](#phase-1-xcframework-build-pipeline)
4. [Phase 2: Swift FFI Bridge Layer](#phase-2-swift-ffi-bridge-layer)
5. [Phase 3: Protobuf for Swift](#phase-3-protobuf-for-swift)
6. [Phase 4: Swift Runtime Client](#phase-4-swift-runtime-client)
7. [Phase 5: Code Generator (Rust → Swift)](#phase-5-code-generator-rust--swift)
8. [Phase 6: Swift Package & Distribution](#phase-6-swift-package--distribution)
9. [Phase 7: Integration Tests](#phase-7-integration-tests)
10. [Open Questions & Risks](#open-questions--risks)

---

## 1. Architecture Overview

The architecture mirrors the Go client with Swift-specific adaptations:

```
┌─────────────────────────────────────────────────────────────┐
│                     User's Swift App                        │
│                                                             │
│   import BamlClient  // generated code                      │
│   let result = try await b.ExtractResume(text: "...")       │
├─────────────────────────────────────────────────────────────┤
│              baml_client/ (generated Swift code)             │
│   - types/        (structs, enums from .baml files)         │
│   - functions.swift  (typed function wrappers)              │
│   - stream_types/ (partial streaming types)                 │
│   - type_map.swift                                          │
├─────────────────────────────────────────────────────────────┤
│            language_client_swift/                            │
│   BamlSwift package (Swift Package Manager)                 │
│   - BamlRuntime.swift     (runtime init, function dispatch) │
│   - Callbacks.swift       (callback registry for async)     │
│   - Serde/                (encode/decode via protobuf)      │
│   - FFIBridge/            (C interop layer)                 │
├─────────────────────────────────────────────────────────────┤
│            language_client_cffi (Rust)                      │
│   - libbaml_cffi.a / .dylib                                 │
│   - C header: baml_cffi_generated.h                         │
│   - Protobuf: baml_{inbound,outbound,object}.proto          │
└─────────────────────────────────────────────────────────────┘
```

### How it works (same as Go)

1. **Swift app** calls a generated function like `b.ExtractResume(text: "...")`
2. **Generated code** encodes arguments into a protobuf `HostFunctionArguments` message
3. **BamlSwift runtime** passes the serialized bytes through the C FFI to `call_function_from_c`
4. **Rust CFFI** spawns an async Tokio task, calls the BAML runtime
5. **Callback** fires back with protobuf-encoded `CFFIValueHolder` result
6. **BamlSwift runtime** decodes the protobuf response into native Swift types
7. **Generated code** casts the decoded result to the expected Swift type

---

## 2. iOS Dynamic Library Strategy

### The Problem

The Go client uses `dlopen` at runtime to load `libbaml_cffi.dylib`/`.so`, downloading it from GitHub releases on first use. This approach **will not work on iOS** for distribution because:

- Apple App Store Review Guideline 2.5.2: *"Apps should be self-contained in their bundles... nor may they download, install, or execute code which introduces or changes features or functionality of the app."*
- All code must be present in the app bundle at submission time
- All binaries must be code-signed by the developer

### The Solution: Two-Track Approach

**`dlopen` itself absolutely works on iOS** for libraries bundled within your app. This is well-documented — see [Lazy Loading Dynamic Libraries and Building Plugin Architectures on iOS](https://medium.com/@cjckytxz/lazy-loading-dynamic-libraries-and-building-plugin-architectures-on-ios-challenge-accepted-a554fccdb84c) by Scott Yelvington (April 2025). The key insight from that article:

> *"While you can load your dylibs lazily, you cannot load them from a remote source. All binaries must be present within your app bundle for the reviewers to review and must be code signed by you the developer."*

The article demonstrates a full working iOS proof-of-concept using `dlopen` with a plugin architecture, loading a framework at runtime on button press and confirming via `lsof` that the framework was NOT loaded at launch time but IS loaded after the button press.

We will support **two linking modes**, split by platform:

#### Default: Static for iOS, Dynamic for macOS

The primary `language_client_swift` client uses a **hybrid approach**:

- **iOS**: Static linking via XCFramework (`.a`). The Rust library gets linked directly into the app binary at compile time. No runtime loading needed. This is the only viable approach for iOS given Apple's restrictions.
  - **Pros**: Simplest iOS integration, no `dlopen` concerns, fastest function call overhead
  - **Cons**: Increases app binary size, requires recompilation for BAML version updates
  - **Distribution**: Swift Package Manager with binary target pointing to XCFramework hosted on GitHub releases

- **macOS**: Dynamic linking with Go-style runtime download. On first use, download `libbaml_cffi.dylib` from GitHub releases, cache locally, and `dlopen` it. This matches the Go client's behavior exactly — no recompilation needed for BAML version updates.

#### Track B (Phase 2): Dynamic Framework with Lazy Loading for iOS

An advanced iOS-only alternative. Compile `baml_cffi` as a **dynamic library** and bundle it as a `.framework` inside the app. Use `dlopen` at runtime for lazy loading — exactly as described in the Yelvington article. The framework is still baked into the `.ipa` (Apple requires this), but it only enters memory when first used.

- **Pros**: Lazy loading means the BAML runtime only enters memory when first used (great for large apps), enables plugin architecture patterns
- **Cons**: More complex Xcode project setup, requires careful build configuration (disabling automatic linking, configuring `@rpath`, `Shared Frameworks` embed phase)
- **Key setup** (per the article):
  1. Bundle `BamlCFFI.framework` in `Shared Frameworks` destination (not the default `Frameworks`)
  2. Disable `Link Frameworks and Libraries Automatically` in Swift Compiler settings
  3. Set `Skip Automatically Linking All Frameworks` to `Yes`
  4. Remove `BamlCFFI.framework` from `Link Binary With Libraries` build phase
  5. Use an interface framework (`BamlSwiftInterface`) shared between app and CFFI framework
  6. Load at runtime via `dlopen(Bundle.main.sharedFrameworksPath! + "/BamlCFFI.framework/BamlCFFI", RTLD_NOW)`
  7. Resolve symbols via `dlsym(handle, "symbol_name")`

**We will implement the default (static iOS + dynamic macOS) first**, then Track B as an opt-in advanced mode for iOS apps with launch-time concerns.

### Rust Compilation Targets

We need to cross-compile `baml_cffi` for these Apple targets:

| Platform | Architecture | Rust Target Triple |
|----------|-------------|-------------------|
| iOS Device | arm64 | `aarch64-apple-ios` |
| iOS Simulator (Apple Silicon) | arm64 | `aarch64-apple-ios-sim` |
| iOS Simulator (Intel) | x86_64 | `x86_64-apple-ios` |
| macOS (Apple Silicon) | arm64 | `aarch64-apple-darwin` |
| macOS (Intel) | x86_64 | `x86_64-apple-darwin` |

The XCFramework bundles all of these into a single distributable artifact.

---

## Phase 1: XCFramework Build Pipeline

### 1.1 Modify `language_client_cffi/Cargo.toml`

Add `staticlib` to the crate-type list so we can produce both `.a` (static) and `.dylib` (dynamic):

```toml
[lib]
crate-type = ["cdylib", "staticlib"]
```

### 1.2 Create Build Script: `build-xcframework.sh`

Location: `engine/language_client_swift/scripts/build-xcframework.sh`

This script will:

1. **Install Rust targets** (if missing):
   ```bash
   rustup target add aarch64-apple-ios
   rustup target add aarch64-apple-ios-sim
   rustup target add x86_64-apple-ios
   rustup target add aarch64-apple-darwin
   rustup target add x86_64-apple-darwin
   ```

2. **Cross-compile** `baml_cffi` for each target:
   ```bash
   cargo build --release --target aarch64-apple-ios -p baml_cffi
   cargo build --release --target aarch64-apple-ios-sim -p baml_cffi
   cargo build --release --target x86_64-apple-ios -p baml_cffi
   cargo build --release --target aarch64-apple-darwin -p baml_cffi
   cargo build --release --target x86_64-apple-darwin -p baml_cffi
   ```

3. **Create fat libraries** for simulator (lipo):
   ```bash
   lipo -create \
     target/aarch64-apple-ios-sim/release/libbaml_cffi.a \
     target/x86_64-apple-ios/release/libbaml_cffi.a \
     -output target/ios-simulator/libbaml_cffi.a

   lipo -create \
     target/aarch64-apple-darwin/release/libbaml_cffi.a \
     target/x86_64-apple-darwin/release/libbaml_cffi.a \
     -output target/macos/libbaml_cffi.a
   ```

4. **Create module map** (`module.modulemap`):
   ```
   module BamlCFFI {
       header "baml_cffi_generated.h"
       link "baml_cffi"
       export *
   }
   ```

5. **Package as XCFramework**:
   ```bash
   xcodebuild -create-xcframework \
     -library target/aarch64-apple-ios/release/libbaml_cffi.a \
     -headers include/ \
     -library target/ios-simulator/libbaml_cffi.a \
     -headers include/ \
     -library target/macos/libbaml_cffi.a \
     -headers include/ \
     -output BamlCFFI.xcframework
   ```

6. **Zip and compute checksum** for SPM binary target:
   ```bash
   zip -r BamlCFFI.xcframework.zip BamlCFFI.xcframework
   swift package compute-checksum BamlCFFI.xcframework.zip
   ```

### 1.3 CI Integration

Add GitHub Actions workflow to:
- Build XCFramework on macOS runners for each release
- Upload `BamlCFFI.xcframework.zip` and `.sha256` as release assets
- Generate/update `Package.swift` checksum

### 1.4 Header Generation

Extend `language_client_cffi/build.rs` to also output the C header to `language_client_swift/`:

```rust
// In build.rs, after the Go header generation block:
{
    let out_path = Path::new(&crate_dir)
        .join("../language_client_swift/include/baml_cffi_generated.h");
    cbindgen::Builder::new()
        .with_config(cbindgen::Config::from_file("cbindgen.toml").unwrap())
        .with_crate(".")
        .generate()
        .expect("Failed to generate C header")
        .write_to_file(out_path);
}
```

---

## Phase 2: Swift FFI Bridge Layer

### 2.1 Directory Structure

```
language_client_swift/
├── Sources/
│   └── BamlSwift/
│       ├── FFIBridge/
│       │   ├── FFIFunctions.swift      // Direct C function calls (static linking)
│       │   ├── DynamicLoader.swift      // dlopen/dlsym path (Track B)
│       │   └── Buffer.swift             // Buffer type mirroring C struct
│       ├── Runtime/
│       │   ├── BamlRuntime.swift        // Main runtime class
│       │   └── Callbacks.swift          // Callback registry (async dispatch)
│       ├── Serde/
│       │   ├── Encode.swift             // Swift → protobuf → C
│       │   └── Decode.swift             // C → protobuf → Swift
│       └── Types/
│           ├── HostValue.swift          // Encoding helpers
│           ├── CFFIValue.swift          // Decoding helpers
│           ├── Media.swift              // Image/Audio/Video/PDF types
│           └── Checked.swift            // Checked<T> type
├── include/
│   ├── baml_cffi_generated.h
│   └── module.modulemap
├── Package.swift
├── scripts/
│   └── build-xcframework.sh
└── IMPLEMENTATION_PLAN.md
```

### 2.2 FFIFunctions.swift (Static Linking Path)

For Track A (static linking), Swift can call the C functions directly since they're linked at compile time:

```swift
import BamlCFFI  // The XCFramework module

/// Thin wrapper around the C FFI functions
internal enum FFI {
    static func createRuntime(
        rootPath: String, srcFilesJson: String, envVarsJson: String
    ) -> UnsafeRawPointer? {
        rootPath.withCString { cRoot in
            srcFilesJson.withCString { cSrc in
                envVarsJson.withCString { cEnv in
                    create_baml_runtime(cRoot, cSrc, cEnv)
                }
            }
        }
    }

    static func callFunction(
        runtime: UnsafeRawPointer,
        functionName: String,
        encodedArgs: Data,
        callId: UInt32
    ) throws {
        let buf = functionName.withCString { cName in
            encodedArgs.withUnsafeBytes { rawBuf in
                let ptr = rawBuf.baseAddress!
                    .assumingMemoryBound(to: CChar.self)
                return call_function_from_c(
                    runtime, cName, ptr, encodedArgs.count, callId
                )
            }
        }
        try decodeAsyncResponse(buf)
    }

    // ... similar wrappers for stream, parse, build_request, cancel, etc.
}
```

### 2.3 DynamicLoader.swift (If we choose Track B — Lazy Loading Path)

For the plugin architecture approach, mirroring the Go client's `dlopen` pattern but adapted for iOS bundles:

```swift
import Foundation

/// Dynamically loads BamlCFFI.framework at runtime (iOS lazy loading)
///
/// Reference: "Lazy Loading Dynamic Libraries and Building Plugin
/// Architectures on iOS" by Scott Yelvington (April 2025)
/// https://medium.com/@cjckytxz/lazy-loading-dynamic-libraries-and-building-plugin-architectures-on-ios-challenge-accepted-a554fccdb84c
///
/// Key requirements for iOS:
/// - Framework MUST be bundled in app (Apple Guideline 2.5.2)
/// - Framework should be in Shared Frameworks destination
/// - Automatic linking must be disabled in Swift compiler settings
/// - Framework must NOT appear in Link Binary With Libraries build phase
internal final class DynamicLoader {
    private var handle: UnsafeMutableRawPointer?

    // Function pointer storage (mirrors Go's wrapper pattern)
    private var fn_version: (@convention(c) () -> Buffer)?
    private var fn_create_runtime: (@convention(c) (
        UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?
    ) -> UnsafeRawPointer?)?
    private var fn_call_function: (@convention(c) (
        UnsafeRawPointer?, UnsafePointer<CChar>?,
        UnsafePointer<CChar>?, Int, UInt32
    ) -> Buffer)?
    // ... etc for all FFI functions

    func load() throws {
        // For iOS: load from app bundle's SharedFrameworks
        let frameworkPath: String
        if let sharedPath = Bundle.main.sharedFrameworksPath {
            frameworkPath = sharedPath + "/BamlCFFI.framework/BamlCFFI"
        } else if let privatePath = Bundle.main.privateFrameworksPath {
            frameworkPath = privatePath + "/BamlCFFI.framework/BamlCFFI"
        } else {
            throw BamlError.libraryNotFound("Could not locate framework bundle path")
        }

        guard let h = dlopen(frameworkPath, RTLD_NOW) else {
            let err = String(cString: dlerror())
            throw BamlError.libraryLoadFailed(err)
        }
        handle = h

        // Resolve all symbols (same pattern as Go's registerFunctions)
        fn_version = resolveSymbol("version")
        fn_create_runtime = resolveSymbol("create_baml_runtime")
        fn_call_function = resolveSymbol("call_function_from_c")
        // ... etc
    }

    private func resolveSymbol<T>(_ name: String) -> T {
        guard let sym = dlsym(handle, name) else {
            fatalError("Failed to resolve symbol: \(name)")
        }
        return unsafeBitCast(sym, to: T.self)
    }
}
```

### 2.4 Callbacks.swift

The callback system is the trickiest part. The Rust CFFI uses C function pointer callbacks (`CallbackFn`, `OnTickCallbackFn`) to deliver async results. Swift needs to:

1. Register global C-compatible callback functions with the Rust runtime
2. Maintain a thread-safe map of `callId → Swift continuation`
3. Bridge from C callbacks to Swift's `async/await`

```swift
import Foundation

/// Thread-safe callback registry mapping call IDs to Swift continuations
internal actor CallbackRegistry {
    private var callbacks: [UInt32: CallbackEntry] = [:]

    struct CallbackEntry {
        let continuation: AsyncStream<CallbackResult>.Continuation
        let isStream: Bool
    }

    func register(id: UInt32, continuation: AsyncStream<CallbackResult>.Continuation, isStream: Bool) {
        callbacks[id] = CallbackEntry(continuation: continuation, isStream: isStream)
    }

    func dispatch(id: UInt32, isDone: Bool, data: Data) {
        guard let entry = callbacks[id] else { return }
        entry.continuation.yield(.success(data: data, isDone: isDone))
        if isDone {
            entry.continuation.finish()
            callbacks.removeValue(forKey: id)
        }
    }

    func dispatchError(id: UInt32, message: String) {
        guard let entry = callbacks[id] else { return }
        entry.continuation.yield(.error(message))
        entry.continuation.finish()
        callbacks.removeValue(forKey: id)
    }
}

// Global C-compatible callback functions registered with Rust
// These MUST be global functions (not closures) for @convention(c)

private let callbackRegistry = CallbackRegistry()

@_cdecl("swift_trigger_callback")
func swiftTriggerCallback(
    callId: UInt32, isDone: Int32,
    content: UnsafePointer<Int8>?, length: Int
) {
    guard let content = content else { return }
    let data = Data(bytes: content, count: length)
    Task {
        await callbackRegistry.dispatch(
            id: callId, isDone: isDone == 1, data: data
        )
    }
}

@_cdecl("swift_error_callback")
func swiftErrorCallback(
    callId: UInt32, isDone: Int32,
    content: UnsafePointer<Int8>?, length: Int
) {
    guard let content = content else { return }
    let message = String(
        bytes: Data(bytes: content, count: length),
        encoding: .utf8
    ) ?? "Unknown error"
    Task {
        await callbackRegistry.dispatchError(id: callId, message: message)
    }
}

@_cdecl("swift_on_tick_callback")
func swiftOnTickCallback(callId: UInt32) {
    // Handle tick events for streaming
}
```

**Critical note**: The Go client uses CGo's `//export` directive to create C-callable functions from Go. In Swift, we use `@_cdecl("name")` to create C-callable functions. These are registered with the Rust side via `register_callbacks()`.

However, there's a type mismatch to handle: the Rust CFFI's `register_callbacks` expects `CallbackFn` which is `void (*)(uint32_t, int32_t, const int8_t*, uintptr_t)`. We need to cast our Swift `@_cdecl` functions to match this signature. The function pointer types should align since `@_cdecl` produces C-compatible function pointers.

---

## Phase 3: Protobuf for Swift

### 3.1 Generate Swift Protobuf Code

The existing proto files in `language_client_cffi/types/baml/cffi/v1/` need Swift code generation. We'll use Apple's `swift-protobuf` library.

**Add to `build.rs`** (following the Go pattern):

```rust
{
    let lang = "swift";
    let lang_dir = format!("../language_client_{lang}/Sources/BamlSwift/Proto");

    let mut protoc = protoc_lang_out::ProtocLangOut::new();
    protoc
        .lang("swift")
        .inputs(protos)
        .includes(["types"])
        .out_dir(lang_dir);

    // Find protoc-gen-swift plugin
    if let Ok(path) = std::env::var("PROTOC_GEN_SWIFT_PATH") {
        protoc.plugin(&path);
    }

    protoc.run()
        .unwrap_or_else(|_| panic!("Failed to generate {lang} bindings"));
}
```

**Proto option for Swift package name** — add to each `.proto` file:

```proto
option swift_prefix = "Baml_";
```

Or handle via `protoc-gen-swift` command-line options to set module mappings.

### 3.2 Generated Swift Proto Files

This will produce:
- `baml_inbound.pb.swift` — `HostValue`, `HostFunctionArguments`, etc.
- `baml_outbound.pb.swift` — `CFFIValueHolder`, `CFFIFieldTypeHolder`, etc.
- `baml_object.pb.swift` — `BamlObjectHandle`, `BamlPointerType`, etc.
- `baml_object_methods.pb.swift` — object method protos

### 3.3 Serde Layer (Encode/Decode)

**Encode.swift** — Swift values → protobuf `HostValue`:

```swift
import SwiftProtobuf

/// Encodes Swift values into protobuf HostValue for sending to BAML runtime
public enum BamlEncoder {

    public static func encodeClass(
        name: String, fields: [String: Any], dynamicFields: [String: Any]? = nil
    ) throws -> Baml_HostValue {
        var classValue = Baml_HostClassValue()
        classValue.name = name
        for (key, value) in fields {
            var entry = Baml_HostMapEntry()
            entry.stringKey = key
            entry.value = try encodeValue(value)
            classValue.fields.append(entry)
        }
        var hostValue = Baml_HostValue()
        hostValue.classValue = classValue
        return hostValue
    }

    public static func encodeEnum(
        name: String, value: String
    ) throws -> Baml_HostValue {
        var enumValue = Baml_HostEnumValue()
        enumValue.name = name
        enumValue.value = value
        var hostValue = Baml_HostValue()
        hostValue.enumValue = enumValue
        return hostValue
    }

    public static func encodeValue(_ value: Any) throws -> Baml_HostValue {
        var hostValue = Baml_HostValue()
        switch value {
        case let s as String:
            hostValue.stringValue = s
        case let i as Int:
            hostValue.intValue = Int64(i)
        case let d as Double:
            hostValue.floatValue = d
        case let b as Bool:
            hostValue.boolValue = b
        case nil:
            // nil = missing value field
            break
        case let arr as [Any]:
            var list = Baml_HostListValue()
            list.values = try arr.map { try encodeValue($0) }
            hostValue.listValue = list
        case let dict as [String: Any]:
            var map = Baml_HostMapValue()
            for (k, v) in dict {
                var entry = Baml_HostMapEntry()
                entry.stringKey = k
                entry.value = try encodeValue(v)
                map.entries.append(entry)
            }
            hostValue.mapValue = map
        default:
            throw BamlError.encodingFailed("Unsupported type: \(type(of: value))")
        }
        return hostValue
    }

    /// Encode function arguments into serialized bytes for FFI
    public static func encodeFunctionArgs(
        kwargs: [String: Any],
        envVars: [String: String] = [:],
        clientRegistry: Baml_HostClientRegistry? = nil
    ) throws -> Data {
        var args = Baml_HostFunctionArguments()
        for (key, value) in kwargs {
            var entry = Baml_HostMapEntry()
            entry.stringKey = key
            entry.value = try encodeValue(value)
            args.kwargs.append(entry)
        }
        for (key, value) in envVars {
            var env = Baml_HostEnvVar()
            env.key = key
            env.value = value
            args.env.append(env)
        }
        if let registry = clientRegistry {
            args.clientRegistry = registry
        }
        return try args.serializedData()
    }
}
```

**Decode.swift** — protobuf `CFFIValueHolder` → Swift values:

```swift
/// Decodes protobuf CFFIValueHolder into native Swift types
public enum BamlDecoder {

    /// Type map: maps BAML type names to Swift metatypes for decoding
    public typealias TypeMap = [String: Any.Type]

    public static func decode(
        _ holder: Baml_CFFIValueHolder, typeMap: TypeMap
    ) -> Any? {
        switch holder.value {
        case .stringValue(let s): return s
        case .intValue(let i): return i
        case .floatValue(let f): return f
        case .boolValue(let b): return b
        case .nullValue: return nil
        case .classValue(let cls):
            return decodeClass(cls, typeMap: typeMap)
        case .enumValue(let e):
            return decodeEnum(e, typeMap: typeMap)
        case .listValue(let list):
            return list.items.map { decode($0, typeMap: typeMap) }
        case .mapValue(let map):
            var dict: [String: Any?] = [:]
            for entry in map.entries {
                dict[entry.key] = decode(entry.value, typeMap: typeMap)
            }
            return dict
        case .unionVariantValue(let union):
            return decode(union.value, typeMap: typeMap)
        case .checkedValue(let checked):
            return decodeChecked(checked, typeMap: typeMap)
        case .streamingStateValue(let state):
            return decodeStreamState(state, typeMap: typeMap)
        case .none:
            return nil
        default:
            return nil
        }
    }

    // ... decodeClass, decodeEnum, decodeChecked, decodeStreamState helpers
}
```

---

## Phase 4: Swift Runtime Client

### 4.1 BamlRuntime.swift

```swift
import Foundation

/// Main BAML runtime for Swift — manages lifecycle and function dispatch
public final class BamlRuntime: @unchecked Sendable {
    private let runtimePtr: UnsafeRawPointer

    public init(rootPath: String, srcFiles: [String: String], envVars: [String: String]) throws {
        let srcJson = try JSONSerialization.data(withJSONObject: srcFiles)
        let envJson = try JSONSerialization.data(withJSONObject: envVars)

        guard let ptr = FFI.createRuntime(
            rootPath: rootPath,
            srcFilesJson: String(data: srcJson, encoding: .utf8)!,
            envVarsJson: String(data: envJson, encoding: .utf8)!
        ) else {
            throw BamlError.runtimeCreationFailed
        }

        self.runtimePtr = ptr

        // Register callbacks on first init
        Self.registerCallbacksOnce()
    }

    deinit {
        FFI.destroyRuntime(runtimePtr)
    }

    private static let callbackRegistration: Void = {
        FFI.registerCallbacks(
            callbackFn: swift_trigger_callback,
            errorCallbackFn: swift_error_callback,
            onTickCallbackFn: swift_on_tick_callback
        )
    }()

    private static func registerCallbacksOnce() { _ = callbackRegistration }

    /// Call a BAML function and await the result
    public func callFunction(
        name: String, args: Data
    ) async throws -> Data {
        let callId = CallbackRegistry.shared.generateId()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                Task {
                    await CallbackRegistry.shared.registerSingle(
                        id: callId, continuation: continuation
                    )
                    do {
                        try FFI.callFunction(
                            runtime: runtimePtr,
                            functionName: name,
                            encodedArgs: args,
                            callId: callId
                        )
                    } catch {
                        await CallbackRegistry.shared.cancel(id: callId)
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            FFI.cancelFunctionCall(id: callId)
        }
    }

    /// Stream a BAML function, yielding partial results
    public func callFunctionStream(
        name: String, args: Data
    ) -> AsyncThrowingStream<Data, Error> {
        let callId = CallbackRegistry.shared.generateId()

        return AsyncThrowingStream { continuation in
            Task {
                await CallbackRegistry.shared.registerStream(
                    id: callId, continuation: continuation
                )
                do {
                    try FFI.callFunctionStream(
                        runtime: runtimePtr,
                        functionName: name,
                        encodedArgs: args,
                        callId: callId
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                FFI.cancelFunctionCall(id: callId)
            }
        }
    }
}
```

### 4.2 Key Design Decisions

- **`async/await` native**: Unlike Go which uses channels, Swift naturally uses `async/await` and `AsyncThrowingStream`. The callback bridge converts C callbacks → `CheckedContinuation` for single calls, `AsyncThrowingStream.Continuation` for streaming.
- **`Sendable` compliance**: `BamlRuntime` is `@unchecked Sendable` because the underlying Rust runtime is thread-safe (it uses `Arc` internally). The raw pointer is safe to share.
- **Cancellation**: Swift's `Task` cancellation maps to `cancel_function_call` which triggers the Rust trip wire mechanism.

---

## Phase 5: Code Generator (Rust → Swift)

### 5.1 New Rust Crate

Create `engine/generators/languages/swift/` following the Go generator pattern:

```
engine/generators/languages/swift/
├── Cargo.toml
├── src/
│   ├── lib.rs           // SwiftLanguageFeatures impl
│   ├── functions.rs     // Function template rendering
│   ├── generated_types.rs // Type template rendering
│   ├── type.rs          // Swift type mapping
│   ├── ir_to_swift/
│   │   ├── mod.rs
│   │   ├── classes.rs   // IR Class → Swift struct
│   │   ├── enums.rs     // IR Enum → Swift enum
│   │   ├── functions.rs // IR Function → Swift func
│   │   ├── unions.rs    // IR Union → Swift enum with associated values
│   │   └── type_aliases.rs
│   └── utils.rs
```

### 5.2 Type Mapping: BAML → Swift

| BAML Type | Swift Type |
|-----------|-----------|
| `string` | `String` |
| `int` | `Int64` |
| `float` | `Double` |
| `bool` | `Bool` |
| `null` | `nil` / `Optional` |
| `class Foo { ... }` | `struct Foo: Codable { ... }` |
| `enum Bar { ... }` | `enum Bar: String, Codable { ... }` |
| `Foo \| Bar` | `enum FooOrBar { case foo(Foo); case bar(Bar) }` |
| `Foo?` | `Optional<Foo>` |
| `Foo[]` | `[Foo]` |
| `map<string, Foo>` | `[String: Foo]` |
| `image` | `BamlImage` |
| `audio` | `BamlAudio` |

### 5.3 Generated Code Example

For a BAML function:
```
function ExtractResume(text: string) -> Resume {
  client GPT4
  prompt #"Extract resume from: {{ text }}"#
}
```

Generated `functions.swift`:
```swift
// AUTO-GENERATED by BAML — do not edit

import BamlSwift

extension BamlClient {
    public func ExtractResume(text: String) async throws -> Resume {
        let args = try BamlEncoder.encodeFunctionArgs(kwargs: [
            "text": try BamlEncoder.encodeValue(text)
        ])
        let resultData = try await runtime.callFunction(
            name: "ExtractResume", args: args
        )
        let holder = try Baml_CFFIValueHolder(serializedBytes: resultData)
        guard let decoded = BamlDecoder.decode(holder, typeMap: typeMap) as? Resume else {
            throw BamlError.decodingFailed("Expected Resume")
        }
        return decoded
    }

    public func ExtractResumeStream(text: String) -> AsyncThrowingStream<StreamState<Resume>, Error> {
        // ... streaming variant
    }
}
```

Generated `types/Resume.swift`:
```swift
// AUTO-GENERATED by BAML — do not edit

public struct Resume: Codable, Sendable {
    public var name: String
    public var email: String?
    public var skills: [String]

    public init(name: String, email: String? = nil, skills: [String] = []) {
        self.name = name
        self.email = email
        self.skills = skills
    }
}
```

### 5.4 Template Engine

Use `askama` templates (same as Go generator). Example template for functions:

```
// functions.swift.askama
import BamlSwift

extension BamlClient {
{% for function in functions %}
    public func {{ function.name }}(
        {%- for arg in function.args %}
        {{ arg.name }}: {{ arg.swift_type }}{% if !loop.last %},{% endif %}
        {%- endfor %}
    ) async throws -> {{ function.return_type }} {
        let args = try BamlEncoder.encodeFunctionArgs(kwargs: [
            {%- for arg in function.args %}
            "{{ arg.name }}": try BamlEncoder.encodeValue({{ arg.name }}){% if !loop.last %},{% endif %}
            {%- endfor %}
        ])
        let resultData = try await runtime.callFunction(
            name: "{{ function.name }}", args: args
        )
        return try decode(resultData)
    }
{% endfor %}
}
```

### 5.5 Files Generated by `baml-cli generate`

```
baml_client/
├── BamlClient.swift           // Main client class with runtime init
├── functions.swift             // Typed function wrappers
├── functions_stream.swift      // Streaming function wrappers
├── types/
│   ├── classes.swift           // All struct types
│   ├── enums.swift             // All enum types
│   └── unions.swift            // Union types as Swift enums
├── stream_types/
│   ├── classes.swift           // Partial streaming structs
│   └── unions.swift
├── type_map.swift              // Maps BAML type names → Swift types
└── baml_source_map.swift       // Embedded .baml source files
```

---

## Phase 6: Publishing, Distribution & CI

### 6.1 How it works today (Go)

The existing release pipeline (`.github/workflows/release.yml` + `build-cli-release.reusable.yaml`) builds `baml_cffi` for 8 platform/arch combinations and uploads them as GitHub release assets:

```
GitHub Release v0.219.0
├── libbaml_cffi-x86_64-apple-darwin.dylib        # macOS Intel
├── libbaml_cffi-x86_64-apple-darwin.dylib.sha256
├── libbaml_cffi-aarch64-apple-darwin.dylib        # macOS ARM
├── libbaml_cffi-aarch64-apple-darwin.dylib.sha256
├── libbaml_cffi-x86_64-unknown-linux-gnu.so       # Linux Intel
├── libbaml_cffi-aarch64-unknown-linux-gnu.so      # Linux ARM
├── libbaml_cffi-x86_64-pc-windows-msvc.dll        # Windows Intel
├── ... (8 total, one per platform/arch)
├── baml-cli-*                                     # CLI binaries
└── CHANGELOG.md
```

The Go SDK downloads the right `.dylib`/`.so` from here at runtime. Swift needs something different.

### 6.2 What Swift needs: XCFramework on GitHub Releases

Swift Package Manager supports **binary targets** — pre-compiled XCFrameworks hosted at a URL. `Package.swift` points to a zip on GitHub releases, and SPM downloads + caches it automatically when the user adds the dependency.

The release would look like:

```
GitHub Release v0.219.0
├── ... (existing Go/CLI artifacts)
│
├── BamlCFFI-static.xcframework.zip                # NEW: for language_client_swift
├── BamlCFFI-static.xcframework.zip.sha256
├── BamlCFFI-dynamic.xcframework.zip               # NEW: for language_client_swift_dynamic
├── BamlCFFI-dynamic.xcframework.zip.sha256
```

### 6.3 Package.swift (static client)

```swift
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
        // Pre-compiled Rust CFFI library as XCFramework
        // SPM downloads this automatically from GitHub releases
        .binaryTarget(
            name: "BamlCFFI",
            url: "https://github.com/boundaryml/baml/releases/download/0.219.0/BamlCFFI-static.xcframework.zip",
            checksum: "CHECKSUM_HERE"
        ),
        .target(
            name: "BamlSwift",
            dependencies: [
                "BamlCFFI",
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ]
        ),
        .testTarget(
            name: "BamlSwiftTests",
            dependencies: ["BamlSwift"]
        ),
    ]
)
```

### 6.4 Package.swift (dynamic client)

```swift
// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BamlSwiftDynamic",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(name: "BamlSwiftDynamic", targets: ["BamlSwiftDynamic"]),
        .library(name: "BamlSwiftInterface", targets: ["BamlSwiftInterface"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-protobuf.git",
            from: "1.28.0"
        ),
    ],
    targets: [
        // The interface framework — lightweight, linked at launch
        .target(
            name: "BamlSwiftInterface"
        ),
        // The runtime package — loader, serde, callbacks
        .target(
            name: "BamlSwiftDynamic",
            dependencies: [
                "BamlSwiftInterface",
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ]
        ),
        // NOTE: BamlCFFI.framework is NOT an SPM dependency for iOS.
        // It must be manually embedded in the Xcode project and placed
        // in Shared Frameworks. See README.md for Xcode setup instructions.
        // On macOS, the framework is downloaded at runtime (Go-style).
    ]
)
```

For the dynamic client on iOS, `BamlCFFI.framework` can't be an SPM binary target because SPM would auto-link it. Instead, it's distributed as a separate download that the developer manually adds to their Xcode project. On macOS, `MacOSDownloader` handles it at runtime.

### 6.5 Repository Structure: Separate Swift Package Repo

A separate repo is required because SPM's `.package(url:)` clones the repo and expects `Package.swift` at the root — there is no subdirectory parameter. Pointing to the monorepo would clone all of `boundaryml/baml` and fail to find the right `Package.swift`. SPM subdirectory support has been requested for years but Apple hasn't shipped it. The standard workaround (used by Firebase, AWS SDK, gRPC-Swift) is a **mirror repo** that CI auto-pushes to on release. If SPM ever adds subdirectory support, these repos become unnecessary.

```
boundaryml/baml              # Main repo (Rust, Go, Python, CFFI, generators)
boundaryml/baml-swift        # Swift static package repo (auto-updated by CI)
boundaryml/baml-swift-dynamic # Swift dynamic package repo (auto-updated by CI)
```

Users add:
```swift
.package(url: "https://github.com/boundaryml/baml-swift.git", from: "0.219.0")
```

The source code for both packages still lives in the main repo under `engine/language_client_swift/` and `engine/language_client_swift_dynamic/`. CI copies the Swift source + generated protobuf code into the respective package repos and tags them.

### 6.6 CI Workflow: `build-swift-release.reusable.yaml`

New reusable workflow that plugs into the existing `release.yml`. Runs on macOS runners (required for iOS cross-compilation and `xcodebuild`).

```yaml
name: Build Swift XCFrameworks

on:
  workflow_call:
    inputs:
      version:
        required: true
        type: string
      is_release:
        required: true
        type: boolean

jobs:
  build-xcframeworks:
    runs-on: macos-14  # Apple Silicon runner (has Xcode 15+)

    steps:
      - uses: actions/checkout@v4

      - name: Install Rust toolchain
        uses: dtolnay/rust-toolchain@stable
        with:
          targets: >-
            aarch64-apple-ios,
            aarch64-apple-ios-sim,
            x86_64-apple-ios,
            aarch64-apple-darwin,
            x86_64-apple-darwin

      - name: Install protoc-gen-swift
        run: brew install swift-protobuf

      # ---- Build static libraries for all targets ----

      - name: Build static libs
        working-directory: engine
        run: |
          for target in aarch64-apple-ios aarch64-apple-ios-sim \
                         x86_64-apple-ios aarch64-apple-darwin \
                         x86_64-apple-darwin; do
            cargo build --release -p baml_cffi --target $target
          done

      # ---- Create fat binaries ----

      - name: Create fat libraries
        run: |
          mkdir -p target/ios-simulator-fat target/macos-fat
          lipo -create \
            target/aarch64-apple-ios-sim/release/libbaml_cffi.a \
            target/x86_64-apple-ios/release/libbaml_cffi.a \
            -output target/ios-simulator-fat/libbaml_cffi.a
          lipo -create \
            target/aarch64-apple-darwin/release/libbaml_cffi.a \
            target/x86_64-apple-darwin/release/libbaml_cffi.a \
            -output target/macos-fat/libbaml_cffi.a

      # ---- Prepare headers + module map ----

      - name: Prepare headers
        run: |
          mkdir -p xcframework-staging/include
          cp engine/language_client_swift/include/baml_cffi_generated.h \
             xcframework-staging/include/
          cat > xcframework-staging/include/module.modulemap << 'EOF'
          module BamlCFFI {
              header "baml_cffi_generated.h"
              link "baml_cffi"
              export *
          }
          EOF

      # ---- Package static XCFramework ----

      - name: Create static XCFramework
        run: |
          xcodebuild -create-xcframework \
            -library target/aarch64-apple-ios/release/libbaml_cffi.a \
            -headers xcframework-staging/include/ \
            -library target/ios-simulator-fat/libbaml_cffi.a \
            -headers xcframework-staging/include/ \
            -library target/macos-fat/libbaml_cffi.a \
            -headers xcframework-staging/include/ \
            -output BamlCFFI-static.xcframework

      - name: Zip and checksum
        run: |
          zip -r BamlCFFI-static.xcframework.zip BamlCFFI-static.xcframework
          shasum -a 256 BamlCFFI-static.xcframework.zip \
            > BamlCFFI-static.xcframework.zip.sha256

      - name: Compute SPM checksum
        id: checksum
        run: |
          CHECKSUM=$(swift package compute-checksum \
            BamlCFFI-static.xcframework.zip)
          echo "checksum=$CHECKSUM" >> "$GITHUB_OUTPUT"

      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: swift-xcframeworks
          path: |
            BamlCFFI-static.xcframework.zip
            BamlCFFI-static.xcframework.zip.sha256
```

### 6.7 CI Workflow: Update `baml-swift` Repo

After XCFramework is built and the GitHub release is created, a second job syncs the Swift package repo:

```yaml
  update-swift-package:
    needs: [build-xcframeworks, publish-to-github]
    if: inputs.is_release
    runs-on: ubuntu-latest

    steps:
      - name: Checkout baml-swift repo
        uses: actions/checkout@v4
        with:
          repository: boundaryml/baml-swift
          token: ${{ secrets.BAML_SWIFT_REPO_TOKEN }}

      - name: Download checksum artifact
        uses: actions/download-artifact@v4
        with:
          name: swift-xcframeworks

      - name: Update Package.swift with new version + checksum
        run: |
          VERSION="${{ inputs.version }}"
          CHECKSUM=$(awk '{print $1}' BamlCFFI-static.xcframework.zip.sha256)

          sed -i "s|releases/download/.*/BamlCFFI|releases/download/${VERSION}/BamlCFFI|g" \
            Package.swift
          sed -i "s|checksum: \".*\"|checksum: \"${CHECKSUM}\"|g" \
            Package.swift
          sed -i "s|let VERSION = \".*\"|let VERSION = \"${VERSION}\"|g" \
            Sources/BamlSwift/Version.swift

      - name: Commit and tag
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add -A
          git commit -m "Release ${{ inputs.version }}"
          git tag "${{ inputs.version }}"
          git push origin main --tags
```

### 6.8 Full Release Flow

```
Developer pushes tag v0.219.0 to boundaryml/baml
        │
        ▼
release.yml triggers
        │
        ├── build-cli-release.reusable.yaml (existing)
        │   └── Builds CFFI for Linux, macOS, Windows (8 targets)
        │       └── Uploads: libbaml_cffi-*.dylib/so/dll
        │
        ├── build-swift-release.reusable.yaml (NEW)
        │   └── Runs on macos-14 runner
        │       ├── Cross-compiles libbaml_cffi.a for 5 Apple targets
        │       ├── lipo → fat binaries for simulator + macOS
        │       ├── xcodebuild -create-xcframework
        │       ├── zip + sha256 + swift package compute-checksum
        │       └── Uploads: BamlCFFI-static.xcframework.zip
        │
        ├── publish-to-github (existing, extended)
        │   └── Creates GitHub Release with ALL artifacts
        │       ├── Go: libbaml_cffi-*.dylib/so/dll
        │       ├── CLI: baml-cli-*
        │       └── Swift: BamlCFFI-static.xcframework.zip (NEW)
        │
        └── update-swift-package (NEW)
            └── Pushes to boundaryml/baml-swift repo
                ├── Updates Package.swift URL + checksum
                ├── Updates version constant
                ├── Commits + tags v0.219.0
                └── SPM users get the update on next resolve
```

### 6.9 Version Synchronization

Same pattern as Go: the Swift runtime has a hardcoded `VERSION` constant. On init, it calls the C FFI `version()` function and asserts the loaded binary matches.

```swift
// Sources/BamlSwift/Version.swift
internal let VERSION = "0.219.0"

// Called during BamlRuntime.init
func verifyVersion() throws {
    let libraryVersion = FFI.version()
    guard libraryVersion == VERSION else {
        throw BamlError.versionMismatch(
            expected: VERSION, got: libraryVersion
        )
    }
}
```

CI updates this constant automatically when a new release is tagged.

### 6.10 What the developer sees

**Adding BAML to a new iOS project:**
```swift
// 1. Add dependency (Xcode UI or Package.swift)
.package(url: "https://github.com/boundaryml/baml-swift.git", from: "0.219.0")

// 2. Generate client code
// $ baml-cli generate --from baml_src --lang swift

// 3. Use it
import BamlSwift
import BamlClient  // generated

let b = try BamlClient()
let resume = try await b.ExtractResume(text: "John Doe, 5 years experience...")
```

**Updating BAML:**
```swift
// Bump the version in Package.swift (or Xcode's package resolution UI)
.package(url: "https://github.com/boundaryml/baml-swift.git", from: "0.220.0")
// SPM downloads the new XCFramework automatically
// Re-run: baml-cli generate
```

---

## Phase 7: Integration Tests

### 7.1 Test Structure

```
integ-tests/swift/
├── Package.swift
├── Sources/
│   └── main.swift           // Test runner
├── baml_src/                // Shared BAML test sources (symlink)
├── baml_client/             // Generated Swift client code
└── Tests/
    ├── BasicFunctionTests.swift
    ├── StreamingTests.swift
    ├── TypeEncodingTests.swift
    └── ErrorHandlingTests.swift
```

### 7.2 Test Plan

1. **Unit tests**: Encode/decode roundtrip for all BAML types
2. **Integration tests**: Call real BAML functions against test LLM providers (we will use openrouter here)
3. **iOS simulator tests**: Verify XCFramework loads correctly on iOS simulator
4. **Lazy loading tests**: Verify `dlopen` path works on iOS simulator (Track B)

---

## Open Questions & Risks

### High Priority

1. **Callback thread safety**: The C callbacks from Rust fire on Tokio threads. Swift's `@_cdecl` functions will be called on arbitrary threads. We need to ensure the dispatch to Swift's actor system is safe. The Go client handles this via goroutines; Swift needs careful use of `Task { }` from C callback context.

2. **`@_cdecl` stability**: `@_cdecl` is technically not a public Swift attribute (underscore prefix). It has been stable for years and is widely used, but it's not officially guaranteed. Alternative: write a small C shim file that wraps the Swift callback functions.

3. **Memory management across FFI boundary**: The `Buffer` struct returned by Rust must be freed with `free_buffer()`. Need to ensure no leaks, possibly with a Swift wrapper type that calls `free_buffer` in `deinit`.

4. **Protobuf dependency size**: `swift-protobuf` adds ~2MB to app binary. For apps that already use protobuf this is free. For others, we could consider a lighter-weight manual serialization layer, but protobuf is the right choice for consistency with Go/Rust.

### Medium Priority

5. **`staticlib` + `cdylib` dual crate-type**: Rust supports both in the same crate, but there may be subtle issues with symbol visibility. Need to verify that `#[no_mangle] pub extern "C"` symbols are exported correctly from the static library.

6. **iOS minimum deployment target**: Rust's `aarch64-apple-ios` target supports iOS 7+, but we should declare iOS 15+ minimum for modern Swift concurrency (`async/await`, actors).

7. **Binary size**: A release-mode `libbaml_cffi.a` for arm64 is likely 15-30MB. We should investigate `strip`, LTO, and `opt-level = "z"` to minimize this. The Go `.dylib` is ~17MB for reference.

### Low Priority

8. **Swift 6 strict concurrency**: Swift 6's strict `Sendable` checking may require additional annotations on generated types. All generated structs should conform to `Sendable`.

9. **visionOS / watchOS / tvOS**: The XCFramework approach naturally extends to other Apple platforms. We just need to add Rust compilation targets.

10. **Xcode integration**: A potential future enhancement is an Xcode build plugin that runs `baml-cli generate` automatically when `.baml` files change.

---

## Two Language Clients

Rather than git branches, we maintain **two separate language client directories** under `engine/`. They share the same code generator and protobuf definitions but differ in how they handle **iOS** linking. Both use dynamic/download for macOS (like Go).

```
engine/
├── language_client_swift/          # iOS: static | macOS: dynamic/download (this directory)
├── language_client_swift_dynamic/  # iOS: dynamic/lazy | macOS: dynamic/download
├── language_client_go/             # (existing)
├── language_client_python/         # (existing)
└── language_client_cffi/           # (shared — produces both .a and .dylib)
```

**Key insight: the only real difference between the two clients is the iOS linking strategy.** macOS always uses Go-style dynamic download in both clients.

### `language_client_swift` (default)

**iOS: static linking. macOS: dynamic linking with Go-style download.** This is the primary and recommended path.

- **iOS**: The BAML CFFI Rust library is compiled as a static library (`.a`), bundled into an XCFramework, and linked into the app binary at compile time via Swift Package Manager. No runtime loading.
- **macOS**: On first use, downloads `libbaml_cffi.dylib` from GitHub releases, caches in `~/Library/Caches/baml/libs/{VERSION}/`, and `dlopen`s it. Identical to the Go client.

**Rollout order:**
1. **iOS static** — Cross-compile `libbaml_cffi.a` for `aarch64-apple-ios` + `aarch64-apple-ios-sim` + `x86_64-apple-ios`, package as XCFramework, distribute via SPM binary target.
2. **macOS dynamic** — Implement Go-style `MacOSDownloader` that downloads `libbaml_cffi.dylib` from GitHub releases at runtime.

**Update model:**
- **iOS**: Developer updates the SPM dependency version (which points to a new XCFramework zip on GitHub releases), recompiles, and ships a new app build.
- **macOS**: Developer bumps the version constant — the new `.dylib` auto-downloads on next run. No recompilation needed for BAML updates.

#### The case for static linking on iOS

A reasonable question: why not just use dynamic for iOS too? Several reasons:

**1. Developer experience is dramatically simpler.**
Static linking means "add SPM dependency, done." No Xcode project surgery. No disabling automatic linking. No interface frameworks. No build phase reconfiguration. The entire BAML integration is one line in `Package.swift`. This matters — complex Xcode setups are a major source of frustration and support tickets for iOS SDK vendors.

**2. The ~17MB binary size is normal for iOS SDKs.**
For reference, common iOS library sizes:

| Library | Approx. size added to binary |
|---------|------------------------------|
| Firebase Analytics | ~8MB |
| Firebase Auth + Firestore | ~20-30MB |
| AWS Amplify | ~15-25MB |
| Realm | ~10MB |
| React Native core | ~5-10MB |
| Google Maps SDK | ~15MB |
| **BAML (estimated)** | **~17MB** |

BAML's size is squarely in the range of SDKs that thousands of production iOS apps already ship. It can also be reduced to ~10-12MB with LTO, `opt-level = "z"`, and `strip`.

**3. On iOS, dynamic doesn't save download size.**
Both approaches add ~17MB to the `.ipa` — with static it's in the executable, with dynamic it's a separate `.framework` file in the bundle. The user downloads the same amount either way. Dynamic only saves *launch-time memory* by deferring when the library enters RAM.

**4. No function pointer indirection.**
Static linking calls C functions directly. Dynamic requires `dlsym` lookups and `unsafeBitCast` to function pointers, adding a (tiny) layer of indirection and a potential source of runtime crashes if signatures drift.

### `language_client_swift_dynamic` (Phase 2 — iOS lazy loading variant)

**iOS: dynamic linking with lazy loading. macOS: same as default (dynamic/download).**

The only difference from the default client is the **iOS** strategy. Instead of static linking, the BAML CFFI Rust library is compiled as a dynamic library (`.framework`) and bundled in the app. It loads via `dlopen` at runtime rather than at link time — the ~17MB BAML runtime only enters memory when the app first uses it. The framework is still baked into the `.ipa` at build time (Apple requires this).

This is an advanced option for large iOS apps with launch-time concerns. macOS behavior is identical to `language_client_swift`.

#### Complete Dynamic Client Architecture

The dynamic client requires **three frameworks** in the app's build graph:

```
┌─────────────────────────────────────────────────────────────────┐
│                        Your iOS App                              │
│                                                                  │
│  import BamlSwiftInterface  // linked at launch (~50KB)          │
│  // BamlCFFI.framework is NOT linked — not imported anywhere     │
│                                                                  │
│  let baml = BamlLoader.shared  // triggers dlopen on first use   │
│  let result = try await baml.callFunction(...)                   │
├──────────────────┬────────────────────┬─────────────────────────┤
│ BamlSwiftDynamic │ BamlSwiftInterface │ BamlCFFI.framework      │
│ .framework       │ .framework         │                         │
│                  │                    │                         │
│ Loader logic,    │ Protocols & types  │ Actual Rust FFI binary  │
│ serde, callbacks │ shared by app and  │ (~17MB)                 │
│ (~2MB)           │ BamlCFFI (~50KB)   │                         │
│                  │                    │                         │
│ LINKED at launch │ LINKED at launch   │ NOT LINKED              │
│                  │                    │ Loaded via dlopen       │
└──────────────────┴────────────────────┴─────────────────────────┘
```

**Why three frameworks?**

The core problem: your app needs to call functions that live inside `BamlCFFI.framework`, but it can't `import BamlCFFI` — if it does, the Swift compiler will auto-link it and it loads at launch (defeating the whole point). The interface framework solves this by defining a shared contract (protocols + types) that both the app and the heavy framework can reference without the app ever touching `BamlCFFI` symbols directly.

#### Directory Structure

```
engine/language_client_swift_dynamic/
├── BamlSwiftDynamic/              # The runtime package (linked at launch)
│   ├── Sources/
│   │   └── BamlSwiftDynamic/
│   │       ├── Loader/
│   │       │   ├── BamlLoader.swift           # Singleton, triggers dlopen
│   │       │   ├── DynamicFFI.swift            # dlsym-based function dispatch
│   │       │   └── MacOSDownloader.swift       # Go-style download for macOS
│   │       ├── Runtime/
│   │       │   ├── BamlRuntime.swift           # Runtime impl (same as static)
│   │       │   └── Callbacks.swift             # Callback registry
│   │       └── Serde/
│   │           ├── Encode.swift
│   │           └── Decode.swift
│   └── Package.swift
│
├── BamlSwiftInterface/            # The interface framework (tiny, linked at launch)
│   ├── Sources/
│   │   └── BamlSwiftInterface/
│   │       ├── BamlRuntimeProtocol.swift       # Protocol defining runtime API
│   │       ├── BamlTypes.swift                 # Shared type definitions
│   │       └── BamlExporter.swift              # @objc protocol for dlsym bridge
│   └── Package.swift
│
├── BamlCFFIExporter/              # Thin Swift layer inside BamlCFFI.framework
│   └── Sources/
│       └── Exporter.swift                      # @_cdecl export function
│
├── scripts/
│   ├── build-dynamic-xcframework.sh            # Builds .framework (dylib) version
│   └── build-interface-framework.sh
│
├── IMPLEMENTATION_PLAN.md
└── README.md                                   # Xcode setup instructions
```

#### Interface Framework: `BamlSwiftInterface`

This is the lightweight shared contract. Both the app and the heavy framework depend on it.

```swift
// BamlSwiftInterface/Sources/BamlSwiftInterface/BamlRuntimeProtocol.swift

import Foundation

/// Protocol defining the BAML runtime API.
/// The app codes against this protocol. The concrete implementation
/// lives inside BamlCFFI.framework and is loaded lazily.
public protocol BamlRuntimeProtocol: AnyObject {
    func callFunction(name: String, args: Data) async throws -> Data
    func callFunctionStream(name: String, args: Data) -> AsyncThrowingStream<Data, Error>
    func callFunctionParse(name: String, args: Data) async throws -> Data
    func buildRequest(name: String, args: Data) async throws -> Data
    func version() -> String
}

/// @objc protocol for the C-symbol bridge. This is what dlsym returns.
/// Must be @objc because we're crossing the dlsym boundary via
/// unsafeBitCast from a C function pointer.
@objc public protocol BamlExporter {
    func exportRuntime(
        rootPath: String, srcFilesJson: String, envVarsJson: String
    ) -> AnyObject  // Returns BamlRuntimeProtocol
}
```

#### Exporter: The `@_cdecl` bridge inside `BamlCFFI.framework`

This thin Swift file gets compiled INTO the dynamic framework alongside the Rust binary. It's the entry point that `dlsym` resolves.

```swift
// BamlCFFIExporter/Sources/Exporter.swift

import Foundation
import BamlSwiftInterface

/// C-callable function that dlsym resolves by name.
/// Returns an object conforming to BamlExporter protocol.
@_cdecl("baml_create_exporter")
public func bamlCreateExporter() -> UnsafeMutableRawPointer {
    let exporter = BamlCFFIExporter()
    return Unmanaged.passRetained(exporter).toOpaque()
}

class BamlCFFIExporter: NSObject, BamlExporter {
    func exportRuntime(
        rootPath: String, srcFilesJson: String, envVarsJson: String
    ) -> AnyObject {
        // Creates the actual runtime using direct C calls to the Rust FFI
        // (since we're inside the framework, we CAN link to the Rust symbols)
        return BamlRuntimeImpl(
            rootPath: rootPath,
            srcFilesJson: srcFilesJson,
            envVarsJson: envVarsJson
        )
    }
}

/// Concrete runtime implementation that calls Rust FFI directly.
/// This class conforms to BamlRuntimeProtocol (from BamlSwiftInterface).
/// It lives inside BamlCFFI.framework so it has direct access to
/// create_baml_runtime, call_function_from_c, etc.
class BamlRuntimeImpl: BamlRuntimeProtocol {
    private let runtimePtr: UnsafeRawPointer

    init(rootPath: String, srcFilesJson: String, envVarsJson: String) {
        // Direct C call — we're inside the framework that links the Rust lib
        self.runtimePtr = rootPath.withCString { cRoot in
            srcFilesJson.withCString { cSrc in
                envVarsJson.withCString { cEnv in
                    create_baml_runtime(cRoot, cSrc, cEnv)
                }
            }
        }!
    }

    func callFunction(name: String, args: Data) async throws -> Data {
        // ... same implementation as static client, using direct C calls
    }

    // ... etc
}
```

#### Loader: `BamlLoader` in the app

```swift
// BamlSwiftDynamic/Sources/BamlSwiftDynamic/Loader/BamlLoader.swift

import Foundation
import BamlSwiftInterface

/// Lazy-loads BamlCFFI.framework on first access.
/// The framework is NOT loaded at app launch — only when `.shared` is first referenced.
public final class BamlLoader {

    /// The loaded runtime. Accessing this for the first time triggers dlopen.
    public static var shared: BamlRuntimeProtocol = {
        let exporter = loadExporter()
        let runtime = exporter.exportRuntime(
            rootPath: BamlConfig.rootPath,
            srcFilesJson: BamlConfig.srcFilesJson,
            envVarsJson: BamlConfig.envVarsJson
        ) as! BamlRuntimeProtocol
        return runtime
    }()

    // --- Private loading machinery ---

    private static var handle: UnsafeMutableRawPointer = {
        let path = resolveFrameworkPath()
        guard let h = dlopen(path, RTLD_NOW) else {
            let err = dlerror().map { String(cString: $0) } ?? "unknown"
            fatalError("Failed to load BamlCFFI.framework: \(err)")
        }
        return h
    }()

    private static func resolveFrameworkPath() -> String {
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        // iOS: framework MUST be in app bundle (Apple Guideline 2.5.2)
        // Look in SharedFrameworks first (recommended), then PrivateFrameworks
        if let shared = Bundle.main.sharedFrameworksPath {
            let path = shared + "/BamlCFFI.framework/BamlCFFI"
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        if let priv = Bundle.main.privateFrameworksPath {
            let path = priv + "/BamlCFFI.framework/BamlCFFI"
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        fatalError("""
            BamlCFFI.framework not found in app bundle.
            Ensure it is added to your target's 'Frameworks, Libraries, and Embedded Content'
            with 'Embed & Sign' enabled and destination set to 'Shared Frameworks'.
            Do NOT add it to the 'Link Binary With Libraries' build phase.
        """)

        #elseif os(macOS)
        // macOS: try Go-style download from GitHub releases
        return MacOSDownloader.findOrDownloadLibrary()
        #endif
    }

    private static func loadExporter() -> BamlExporter {
        guard let sym = dlsym(handle, "baml_create_exporter") else {
            fatalError("Failed to resolve baml_create_exporter symbol")
        }
        typealias ExporterFactory = @convention(c) () -> UnsafeMutableRawPointer
        let factory = unsafeBitCast(sym, to: ExporterFactory.self)
        let rawPtr = factory()
        let exporter = Unmanaged<AnyObject>.fromOpaque(rawPtr)
            .takeRetainedValue() as! BamlExporter
        return exporter
    }
}
```

#### macOS Downloader (Go-style)

```swift
// BamlSwiftDynamic/Sources/BamlSwiftDynamic/Loader/MacOSDownloader.swift

#if os(macOS)
import Foundation

/// Downloads libbaml_cffi.dylib from GitHub releases on macOS.
/// Mirrors the Go client's findOrDownloadLibrary() in lib_common.go.
internal enum MacOSDownloader {
    static let version = "0.219.0"
    private static let githubRepo = "boundaryml/baml"
    private static let cacheSubdir = "baml/libs"

    static func findOrDownloadLibrary() -> String {
        // 1. Check BAML_LIBRARY_PATH env var
        if let envPath = ProcessInfo.processInfo.environment["BAML_LIBRARY_PATH"],
           FileManager.default.fileExists(atPath: envPath) {
            return envPath
        }

        // 2. Check cache directory
        let cacheDir = getCacheDir()
        let filename = "libbaml_cffi-\(targetTriple()).dylib"
        let cachedPath = (cacheDir as NSString).appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: cachedPath) {
            return cachedPath
        }

        // 3. Check if downloads disabled
        if ProcessInfo.processInfo.environment["BAML_LIBRARY_DISABLE_DOWNLOAD"]?
            .lowercased() == "true" {
            fatalError("BAML library not found and download disabled")
        }

        // 4. Download from GitHub releases
        let url = "https://github.com/\(githubRepo)/releases/download/\(version)/\(filename)"
        download(from: url, to: cachedPath)

        return cachedPath
    }

    private static func targetTriple() -> String {
        #if arch(arm64)
        return "aarch64-apple-darwin"
        #elseif arch(x86_64)
        return "x86_64-apple-darwin"
        #else
        fatalError("Unsupported architecture")
        #endif
    }

    private static func getCacheDir() -> String {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("\(cacheSubdir)/\(version)").path
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
        return dir
    }

    private static func download(from urlString: String, to destPath: String) {
        // Synchronous download (called during init, same as Go)
        guard let url = URL(string: urlString) else {
            fatalError("Invalid download URL: \(urlString)")
        }
        let semaphore = DispatchSemaphore(value: 0)
        var downloadError: Error?

        let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
            defer { semaphore.signal() }
            if let error = error { downloadError = error; return }
            guard let tempURL = tempURL,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                downloadError = NSError(domain: "BamlDownload", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"])
                return
            }
            do {
                try FileManager.default.moveItem(atPath: tempURL.path, toPath: destPath)
                // Make executable
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755], ofItemAtPath: destPath
                )
            } catch { downloadError = error }
        }
        task.resume()
        semaphore.wait()

        if let error = downloadError {
            fatalError("Failed to download BAML library from \(urlString): \(error)")
        }
    }
}
#endif
```

#### Required Xcode Configuration for iOS Dynamic

Developers using `language_client_swift_dynamic` on iOS must configure their Xcode project as follows. This is the setup described in the Yelvington article:

**Step 1: Add frameworks to embed section**
- In target → General → Frameworks, Libraries, and Embedded Content:
  - Add `BamlSwiftDynamic.framework` — Embed & Sign
  - Add `BamlSwiftInterface.framework` — Embed & Sign
  - Add `BamlCFFI.framework` — Embed & Sign

**Step 2: Move BamlCFFI to Shared Frameworks**
- In target → Build Phases → Embed Frameworks:
  - Change `BamlCFFI.framework` destination to **Shared Frameworks**
  - Leave the other two on default destination

**Step 3: Remove BamlCFFI from link phase**
- In target → Build Phases → Link Binary With Libraries:
  - **Remove** `BamlCFFI.framework` (must NOT be here)
  - Keep `BamlSwiftDynamic.framework` and `BamlSwiftInterface.framework`

**Step 4: Disable automatic linking (recommended)**
- In target → Build Settings:
  - `Link Frameworks and Libraries Automatically` → **No**
  - `Skip Automatically Linking All Frameworks` → **Yes**
- If you enable this, you must manually add all system frameworks (SwiftUI, Foundation, etc.) to the Link phase. This prevents the Swift compiler from detecting any leaked `BamlCFFI` symbol references and force-linking the framework.

**Step 5: Verify**
- Build and run on iOS Simulator
- Use `lsof -p <PID>` to confirm `BamlCFFI.framework` is NOT loaded at launch
- Trigger a BAML call, run `lsof` again — `BamlCFFI.framework` should now appear

#### Why iOS dynamic can't download from GitHub at runtime

Two layers of enforcement, both hard blockers:

**1. App Store Review (policy):** Apple Guideline 2.5.2 — your app gets rejected if it downloads and executes code.

**2. iOS Sandbox + Code Signing (technical):** Even without App Review, the OS itself prevents it:
- Every binary loaded via `dlopen` must have a valid code signature chaining back to your app's provisioning profile
- Code signatures are applied at build time by Xcode and verified by the kernel at load time
- Writable directories (Documents, Caches, tmp) are marked non-executable by the sandbox
- The app bundle (where executables can live) is read-only at runtime
- Catch-22: you can write to Caches but can't execute from there; you can execute from the bundle but can't write to it

### What's shared between the two clients

| Component | Shared? | Location |
|-----------|---------|----------|
| Protobuf definitions (`.proto`) | Yes | `language_client_cffi/types/` |
| Generated Swift protobuf code | Yes | Can be a shared SPM target or generated into both |
| C header (`baml_cffi_generated.h`) | Yes | `language_client_cffi` build output |
| Code generator (Rust → Swift) | Yes | `generators/languages/swift/` |
| Serde layer (encode/decode) | Yes | Can be a shared SPM target |
| FFI bridge layer | **No** | Static uses direct C calls; dynamic uses `dlopen`/`dlsym` |
| Runtime client | **Mostly** | Core logic shared, but init/loading differs |

In practice, we can structure this as a shared `BamlSwiftCore` SPM target (serde, protobuf, callback registry, types) consumed by both `BamlSwift` (static) and `BamlSwiftDynamic` (dynamic), which only differ in how they acquire function pointers to the CFFI.

### Why macOS always uses dynamic download (like Go)

macOS has no App Store restriction on `dlopen` with arbitrary paths. We download `libbaml_cffi.dylib` from GitHub releases, cache in `~/Library/Caches/baml/libs/{VERSION}/`, and `dlopen` it — exact same pattern as `language_client_go/baml_go/lib_common.go`. This is the default for **both** Swift clients on macOS.

### Why iOS can never download at runtime

| Platform | Can download `.dylib` at runtime? | Why? |
|----------|----------------------------------|------|
| **macOS** | **Yes** — identical to Go | No sandbox restrictions on `dlopen` with arbitrary paths. |
| **iOS (App Store)** | **No** | Apple Guideline 2.5.2: *"Apps should be self-contained in their bundles... nor may they download, install, or execute code."* All binaries must be present in the `.ipa`, code-signed by the developer. |
| **iOS (Enterprise / TestFlight)** | **No** | Same code signing and sandboxing restrictions apply. Writable directories are non-executable; the app bundle is read-only. |

**Bottom line:** On iOS, the framework binary is always frozen at build time. The only question is *how* it's linked — static (part of the binary) vs. dynamic (bundled `.framework` loaded lazily via `dlopen`). To update BAML on iOS, you must ship a new app build.

### Summary Matrix

| | `language_client_swift` | `language_client_swift_dynamic` |
|---|---|---|
| **iOS linking** | Static (`.a` in XCFramework) | Dynamic (`.framework` in app bundle) |
| **macOS linking** | Dynamic (`dlopen` from cache / GitHub) | Dynamic (`dlopen` from cache / GitHub) |
| **iOS library loading** | At app launch (part of binary) | Lazy (on first BAML call via `dlopen`) |
| **macOS library loading** | Lazy (on first BAML call via `dlopen`) | Lazy (on first BAML call via `dlopen`) |
| **iOS update model** | Bump SPM version, rebuild app | Bump SPM version, rebuild app |
| **macOS update model** | Bump version constant, auto-downloads | Bump version constant, auto-downloads |
| **iOS binary size impact** | +~17MB to app executable | +~17MB to app bundle (separate file) |
| **macOS binary size impact** | ~0 (downloaded to cache on demand) | ~0 (downloaded to cache on demand) |
| **Best for** | Most apps, simplest iOS setup | Large iOS apps with launch-time concerns |

---

## Implementation Order

### Milestone 1: `language_client_swift` (iOS static + macOS dynamic) — P0

| Phase | Dependency |
|-------|------------|
| Phase 1: XCFramework pipeline (iOS targets only) | None |
| Phase 2: FFI bridge (static C calls for iOS, `dlopen`/`dlsym` for macOS) | Phase 1 |
| Phase 3: Protobuf for Swift | Phase 1 (build.rs) |
| Phase 4: Runtime client + macOS dynamic download (Go-style `MacOSDownloader`) | Phase 2 + 3 |
| Phase 5: Code generator (Rust → Swift) | Phase 4 |
| Phase 6: SPM packaging | Phase 1 + 4 |
| Phase 7: Integration tests (iOS simulator + macOS) | Phase 5 |

### Milestone 2: `language_client_swift_dynamic` (iOS lazy loading) — P1

| Phase | Dependency |
|-------|------------|
| Phase D-1: Extract shared `BamlSwiftCore` SPM target (serde, protobuf, callbacks, macOS downloader) | Milestone 1 |
| Phase D-2: Interface framework + lazy `dlopen` for iOS | Phase D-1 |
| Phase D-3: Integration tests (lazy loading verification via `lsof` on iOS simulator) | Phase D-2 |