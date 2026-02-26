import Foundation
import BamlCFFI

/// Thin wrapper around the C FFI functions for static linking (iOS).
/// On macOS, these are resolved via dlopen/dlsym at runtime.
internal enum FFI {

    // MARK: - Function pointer storage (for macOS dynamic loading)

    #if os(macOS)
    // On macOS, these are set by DynamicLoader. On iOS, they call C symbols directly.
    private static var _version: (@convention(c) () -> BamlCFFI.Buffer)?
    private static var _createRuntime: (@convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> UnsafeRawPointer?)?
    private static var _destroyRuntime: (@convention(c) (UnsafeRawPointer?) -> Void)?
    private static var _registerCallbacks: (@convention(c) (CallbackFn?, CallbackFn?, OnTickCallbackFn?) -> Void)?
    private static var _callFunction: (@convention(c) (UnsafeRawPointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, Int, UInt32) -> BamlCFFI.Buffer)?
    private static var _callFunctionStream: (@convention(c) (UnsafeRawPointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, Int, UInt32) -> BamlCFFI.Buffer)?
    private static var _callFunctionParse: (@convention(c) (UnsafeRawPointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, Int, UInt32) -> BamlCFFI.Buffer)?
    private static var _buildRequest: (@convention(c) (UnsafeRawPointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, Int, UInt32) -> BamlCFFI.Buffer)?
    private static var _cancelFunctionCall: (@convention(c) (UInt32) -> BamlCFFI.Buffer)?
    private static var _callObjectConstructor: (@convention(c) (UnsafePointer<CChar>?, Int) -> BamlCFFI.Buffer)?
    private static var _callObjectMethod: (@convention(c) (UnsafeRawPointer?, UnsafePointer<CChar>?, Int) -> BamlCFFI.Buffer)?
    private static var _freeBuffer: (@convention(c) (BamlCFFI.Buffer) -> Void)?

    /// Called by DynamicLoader after resolving all symbols
    static func setDynamicFunctions(
        version: @escaping @convention(c) () -> BamlCFFI.Buffer,
        createRuntime: @escaping @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> UnsafeRawPointer?,
        destroyRuntime: @escaping @convention(c) (UnsafeRawPointer?) -> Void,
        registerCallbacks: @escaping @convention(c) (CallbackFn?, CallbackFn?, OnTickCallbackFn?) -> Void,
        callFunction: @escaping @convention(c) (UnsafeRawPointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, Int, UInt32) -> BamlCFFI.Buffer,
        callFunctionStream: @escaping @convention(c) (UnsafeRawPointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, Int, UInt32) -> BamlCFFI.Buffer,
        callFunctionParse: @escaping @convention(c) (UnsafeRawPointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, Int, UInt32) -> BamlCFFI.Buffer,
        buildRequest: @escaping @convention(c) (UnsafeRawPointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, Int, UInt32) -> BamlCFFI.Buffer,
        cancelFunctionCall: @escaping @convention(c) (UInt32) -> BamlCFFI.Buffer,
        callObjectConstructor: @escaping @convention(c) (UnsafePointer<CChar>?, Int) -> BamlCFFI.Buffer,
        callObjectMethod: @escaping @convention(c) (UnsafeRawPointer?, UnsafePointer<CChar>?, Int) -> BamlCFFI.Buffer,
        freeBuffer: @escaping @convention(c) (BamlCFFI.Buffer) -> Void
    ) {
        _version = version
        _createRuntime = createRuntime
        _destroyRuntime = destroyRuntime
        _registerCallbacks = registerCallbacks
        _callFunction = callFunction
        _callFunctionStream = callFunctionStream
        _callFunctionParse = callFunctionParse
        _buildRequest = buildRequest
        _cancelFunctionCall = cancelFunctionCall
        _callObjectConstructor = callObjectConstructor
        _callObjectMethod = callObjectMethod
        _freeBuffer = freeBuffer
    }
    #endif

    // MARK: - Version

    static func getVersion() -> String {
        #if os(macOS)
        let buf = FFIBuffer(_version!())
        #else
        let buf = FFIBuffer(version())
        #endif
        return String(data: buf.data, encoding: .utf8) ?? ""
    }

    // MARK: - Runtime lifecycle

    static func createRuntime(
        rootPath: String,
        srcFilesJson: String,
        envVarsJson: String
    ) -> UnsafeRawPointer? {
        return rootPath.withCString { cRoot in
            srcFilesJson.withCString { cSrc in
                envVarsJson.withCString { cEnv in
                    #if os(macOS)
                    return _createRuntime!(cRoot, cSrc, cEnv)
                    #else
                    return create_baml_runtime(cRoot, cSrc, cEnv)
                    #endif
                }
            }
        }
    }

    static func destroyRuntime(_ runtime: UnsafeRawPointer) {
        #if os(macOS)
        _destroyRuntime!(runtime)
        #else
        destroy_baml_runtime(runtime)
        #endif
    }

    // MARK: - Callback registration

    static func registerCallbacks(
        callbackFn: CallbackFn?,
        errorCallbackFn: CallbackFn?,
        onTickCallbackFn: OnTickCallbackFn?
    ) {
        #if os(macOS)
        _registerCallbacks!(callbackFn, errorCallbackFn, onTickCallbackFn)
        #else
        register_callbacks(callbackFn, errorCallbackFn, onTickCallbackFn)
        #endif
    }

    // MARK: - Function calls

    static func callFunction(
        runtime: UnsafeRawPointer,
        functionName: String,
        encodedArgs: Data,
        callId: UInt32
    ) throws {
        let buf = functionName.withCString { cName in
            encodedArgs.withUnsafeBytes { rawBuf -> BamlCFFI.Buffer in
                let ptr = rawBuf.baseAddress?.assumingMemoryBound(to: CChar.self)
                #if os(macOS)
                return _callFunction!(runtime, cName, ptr, encodedArgs.count, callId)
                #else
                return call_function_from_c(runtime, cName, ptr, UInt(encodedArgs.count), callId)
                #endif
            }
        }
        try decodeAsyncResponse(buf)
    }

    static func callFunctionStream(
        runtime: UnsafeRawPointer,
        functionName: String,
        encodedArgs: Data,
        callId: UInt32
    ) throws {
        let buf = functionName.withCString { cName in
            encodedArgs.withUnsafeBytes { rawBuf -> BamlCFFI.Buffer in
                let ptr = rawBuf.baseAddress?.assumingMemoryBound(to: CChar.self)
                #if os(macOS)
                return _callFunctionStream!(runtime, cName, ptr, encodedArgs.count, callId)
                #else
                return call_function_stream_from_c(runtime, cName, ptr, UInt(encodedArgs.count), callId)
                #endif
            }
        }
        try decodeAsyncResponse(buf)
    }

    static func callFunctionParse(
        runtime: UnsafeRawPointer,
        functionName: String,
        encodedArgs: Data,
        callId: UInt32
    ) throws {
        let buf = functionName.withCString { cName in
            encodedArgs.withUnsafeBytes { rawBuf -> BamlCFFI.Buffer in
                let ptr = rawBuf.baseAddress?.assumingMemoryBound(to: CChar.self)
                #if os(macOS)
                return _callFunctionParse!(runtime, cName, ptr, encodedArgs.count, callId)
                #else
                return call_function_parse_from_c(runtime, cName, ptr, UInt(encodedArgs.count), callId)
                #endif
            }
        }
        try decodeAsyncResponse(buf)
    }

    static func buildRequest(
        runtime: UnsafeRawPointer,
        functionName: String,
        encodedArgs: Data,
        callId: UInt32
    ) throws {
        let buf = functionName.withCString { cName in
            encodedArgs.withUnsafeBytes { rawBuf -> BamlCFFI.Buffer in
                let ptr = rawBuf.baseAddress?.assumingMemoryBound(to: CChar.self)
                #if os(macOS)
                return _buildRequest!(runtime, cName, ptr, encodedArgs.count, callId)
                #else
                return build_request_from_c(runtime, cName, ptr, UInt(encodedArgs.count), callId)
                #endif
            }
        }
        try decodeAsyncResponse(buf)
    }

    static func cancelFunctionCall(id: UInt32) {
        #if os(macOS)
        let buf = _cancelFunctionCall!(id)
        _freeBuffer!(buf)
        #else
        let buf = cancel_function_call(id)
        free_buffer(buf)
        #endif
    }

    // MARK: - Free buffer (called by FFIBuffer.deinit on macOS)

    static func freeBuffer(_ buf: BamlCFFI.Buffer) {
        #if os(macOS)
        _freeBuffer?(buf)
        #else
        free_buffer(buf)
        #endif
    }

    // MARK: - Object operations

    static func callObjectConstructor(encodedArgs: Data) throws -> Data {
        let buf = encodedArgs.withUnsafeBytes { rawBuf -> BamlCFFI.Buffer in
            let ptr = rawBuf.baseAddress?.assumingMemoryBound(to: CChar.self)
            #if os(macOS)
            return _callObjectConstructor!(ptr, encodedArgs.count)
            #else
            return call_object_constructor(ptr, UInt(encodedArgs.count))
            #endif
        }
        let wrapper = FFIBuffer(buf)
        return wrapper.data
    }

    static func callObjectMethod(runtime: UnsafeRawPointer, encodedArgs: Data) throws -> Data {
        let buf = encodedArgs.withUnsafeBytes { rawBuf -> BamlCFFI.Buffer in
            let ptr = rawBuf.baseAddress?.assumingMemoryBound(to: CChar.self)
            #if os(macOS)
            return _callObjectMethod!(runtime, ptr, encodedArgs.count)
            #else
            return call_object_method(runtime, ptr, UInt(encodedArgs.count))
            #endif
        }
        let wrapper = FFIBuffer(buf)
        return wrapper.data
    }

    // MARK: - Helpers

    /// Decode the InvocationResponse from an async call.
    /// Empty buffer = success (task spawned). Non-empty = error.
    private static func decodeAsyncResponse(_ buf: BamlCFFI.Buffer) throws {
        let wrapper = FFIBuffer(buf)
        if wrapper.isEmpty { return }

        // Non-empty means error — try to parse as InvocationResponse
        do {
            let response = try Baml_Cffi_V1_InvocationResponse(serializedBytes: wrapper.data)
            if case .error(let message) = response.response {
                throw BamlError.ffiError(message)
            }
        } catch let error as BamlError {
            throw error
        } catch {
            // If we can't parse it as protobuf, treat the raw bytes as an error string
            let message = String(data: wrapper.data, encoding: .utf8) ?? "Unknown FFI error"
            throw BamlError.ffiError(message)
        }
    }
}
