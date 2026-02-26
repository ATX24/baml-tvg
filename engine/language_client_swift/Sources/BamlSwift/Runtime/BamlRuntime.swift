import Foundation

/// Main BAML runtime for Swift.
/// Manages the Rust runtime lifecycle and dispatches function calls.
///
/// - On iOS: Uses statically linked C functions (XCFramework)
/// - On macOS: Downloads and loads libbaml_cffi.dylib at runtime (like Go)
public final class BamlRuntime: @unchecked Sendable {
    private let runtimePtr: UnsafeRawPointer

    /// The BAML version string from the loaded library.
    public static var libraryVersion: String { FFI.getVersion() }

    /// Expected version — updated by CI on each release.
    internal static let expectedVersion = "0.219.0"

    /// Initialize the BAML runtime.
    ///
    /// - Parameters:
    ///   - rootPath: The root path for BAML file resolution
    ///   - srcFiles: Map of filename → file content for .baml source files
    ///   - envVars: Environment variables to pass to the runtime
    public init(rootPath: String, srcFiles: [String: String], envVars: [String: String] = [:]) throws {
        // Ensure library is loaded (no-op on iOS, loads dylib on macOS)
        try Self.ensureLoaded()

        let srcJson = try JSONSerialization.data(withJSONObject: srcFiles)
        let envJson = try JSONSerialization.data(withJSONObject: envVars)

        guard let srcJsonStr = String(data: srcJson, encoding: .utf8),
              let envJsonStr = String(data: envJson, encoding: .utf8) else {
            throw BamlError.runtimeCreationFailed("Failed to encode arguments as JSON")
        }

        guard let ptr = FFI.createRuntime(
            rootPath: rootPath,
            srcFilesJson: srcJsonStr,
            envVarsJson: envJsonStr
        ) else {
            throw BamlError.runtimeCreationFailed("create_baml_runtime returned null")
        }

        self.runtimePtr = ptr

        // Register callbacks on first runtime creation
        Self.registerCallbacksOnce()
    }

    deinit {
        FFI.destroyRuntime(runtimePtr)
    }

    // MARK: - One-time initialization

    private static var _loaded = false
    private static let loadLock = NSLock()

    private static func ensureLoaded() throws {
        loadLock.lock()
        defer { loadLock.unlock() }

        if _loaded { return }

        #if os(macOS)
        try DynamicLoader.shared.load()
        #endif

        // Verify version
        let libVersion = FFI.getVersion()
        guard libVersion == expectedVersion else {
            throw BamlError.versionMismatch(expected: expectedVersion, got: libVersion)
        }

        _loaded = true
    }

    private static let callbackRegistration: Void = {
        FFI.registerCallbacks(
            callbackFn: CallbackPointers.trigger,
            errorCallbackFn: CallbackPointers.error,
            onTickCallbackFn: CallbackPointers.onTick
        )
    }()

    private static func registerCallbacksOnce() { _ = callbackRegistration }

    // MARK: - Function calls

    /// Call a BAML function and await the result.
    /// Returns the raw protobuf-encoded result bytes (CFFIValueHolder).
    public func callFunction(name: String, args: Data) async throws -> Data {
        let callId = CallbackRegistry.shared.generateId()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                CallbackRegistry.shared.registerSingle(
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
                    CallbackRegistry.shared.cancelSingle(id: callId)
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            FFI.cancelFunctionCall(id: callId)
        }
    }

    /// Stream a BAML function, yielding partial results.
    /// Each yielded Data is a protobuf-encoded CFFIValueHolder.
    public func callFunctionStream(name: String, args: Data) -> AsyncThrowingStream<Data, Error> {
        let callId = CallbackRegistry.shared.generateId()

        return AsyncThrowingStream { continuation in
            CallbackRegistry.shared.registerStream(
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

            continuation.onTermination = { @Sendable _ in
                FFI.cancelFunctionCall(id: callId)
            }
        }
    }

    /// Parse raw LLM output into structured types.
    /// Returns the raw protobuf-encoded result bytes.
    public func callFunctionParse(name: String, args: Data) async throws -> Data {
        let callId = CallbackRegistry.shared.generateId()

        return try await withCheckedThrowingContinuation { continuation in
            CallbackRegistry.shared.registerSingle(
                id: callId, continuation: continuation
            )
            do {
                try FFI.callFunctionParse(
                    runtime: runtimePtr,
                    functionName: name,
                    encodedArgs: args,
                    callId: callId
                )
            } catch {
                CallbackRegistry.shared.cancelSingle(id: callId)
                continuation.resume(throwing: error)
            }
        }
    }

    /// Build an HTTP request without executing it.
    /// Returns the raw protobuf-encoded result bytes.
    public func buildRequest(name: String, args: Data) async throws -> Data {
        let callId = CallbackRegistry.shared.generateId()

        return try await withCheckedThrowingContinuation { continuation in
            CallbackRegistry.shared.registerSingle(
                id: callId, continuation: continuation
            )
            do {
                try FFI.buildRequest(
                    runtime: runtimePtr,
                    functionName: name,
                    encodedArgs: args,
                    callId: callId
                )
            } catch {
                CallbackRegistry.shared.cancelSingle(id: callId)
                continuation.resume(throwing: error)
            }
        }
    }

    /// The raw runtime pointer for advanced use (e.g., object method calls).
    internal var pointer: UnsafeRawPointer { runtimePtr }
}
