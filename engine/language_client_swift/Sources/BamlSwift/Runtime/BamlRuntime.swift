import Foundation
import SwiftProtobuf
import BamlCFFI

/// The main entry point for calling BAML from Swift.
///
/// Usage:
///   try loadBamlLibrary(path: "/path/to/libbaml_cffi.dylib")
///   let runtime = try BamlRuntime(rootPath: ".", srcFiles: [...], envVars: [...])
///   let result  = try await runtime.callFunction(name: "MyFn", kwargs: ["name": "World"])
public final class BamlRuntime {
    private let ptr: OpaquePointer

    /// Create a BAML runtime from inline source files.
    ///
    /// - Parameters:
    ///   - rootPath:  Conceptual root path for the BAML project (used in error messages).
    ///   - srcFiles:  Map of relative filename → BAML source content.
    ///   - envVars:   Environment variables exposed to the runtime (e.g. API keys).
    public init(
        rootPath: String,
        srcFiles: [String: String],
        envVars: [String: String] = [:]
    ) throws {
        // create_baml_runtime takes plain JSON strings, not protobuf
        let srcJSON = try String(data: JSONSerialization.data(withJSONObject: srcFiles), encoding: .utf8)!
        let envJSON = try String(data: JSONSerialization.data(withJSONObject: envVars),  encoding: .utf8)!

        let rawPtr = rootPath.withCString { rootCStr in
            srcJSON.withCString { srcCStr in
                envJSON.withCString { envCStr in
                    baml_create_runtime(rootCStr, srcCStr, envCStr)
                }
            }
        }
        guard let rawPtr else { throw BamlError.runtimeCreationFailed }
        self.ptr = OpaquePointer(rawPtr)
    }

    deinit {
        baml_destroy_runtime(UnsafeRawPointer(ptr))
    }

    // -------------------------------------------------------------------------
    // MARK: - version()
    // -------------------------------------------------------------------------

    /// Returns the BAML runtime version string, e.g. "0.219.0".
    public static func version() throws -> String {
        let buf = baml_version()
        guard let data = readAndFreeBuffer(buf),
              let str = String(data: data, encoding: .utf8)
        else { return "" }
        return str
    }

    // -------------------------------------------------------------------------
    // MARK: - callFunction
    // -------------------------------------------------------------------------

    /// Call a BAML function by name and decode the result.
    /// Returns the raw `CFFIValueHolder` — pass it to `decode(_:)` for a Swift value.
    public func callFunction(
        name: String,
        args: Baml_Cffi_V1_HostFunctionArguments
    ) async throws -> Baml_Cffi_V1_CFFIValueHolder {
        let id = registryNextID()
        let encodedArgs = try args.serializedData()

        let resultData = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            registryStore(id: id, continuation: cont)

            let buf = encodedArgs.withUnsafeBytes { rawBuf -> BamlBuffer in
                let charPtr = rawBuf.baseAddress!.assumingMemoryBound(to: CChar.self)
                return name.withCString { nameCStr in
                    baml_call_function(
                        UnsafeRawPointer(ptr),
                        nameCStr,
                        charPtr,
                        UInt(encodedArgs.count),
                        id
                    )
                }
            }

            // The immediate return of call_function_from_c is an InvocationResponse:
            // - empty  → task spawned, callback will fire later
            // - non-empty → immediate error (e.g. unknown function name)
            if let immediateErr = readAndFreeBuffer(buf) {
                let msg: String
                if let r = try? Baml_Cffi_V1_InvocationResponse(serializedBytes: immediateErr),
                   case .error(let e) = r.response {
                    msg = e
                } else {
                    msg = String(data: immediateErr, encoding: .utf8) ?? "unknown error"
                }
                registryFail(id: id, error: BamlError.functionCallFailed(msg))
            }
        }

        return try Baml_Cffi_V1_CFFIValueHolder(serializedBytes: resultData)
    }
}
