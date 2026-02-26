#if os(macOS)
import Foundation

/// Dynamically loads libbaml_cffi.dylib on macOS at runtime.
/// Mirrors the Go client's dlopen approach from lib_common.go.
internal final class DynamicLoader {
    private var handle: UnsafeMutableRawPointer?

    static let shared = DynamicLoader()

    private init() {}

    /// Load the dynamic library and resolve all symbols.
    /// Must be called before any FFI function is used on macOS.
    func load() throws {
        let path = try MacOSDownloader.findOrDownloadLibrary()

        guard let h = dlopen(path, RTLD_NOW) else {
            let err = dlerror().map { String(cString: $0) } ?? "unknown dlopen error"
            throw BamlError.libraryLoadFailed(err)
        }
        handle = h

        // Resolve all symbols and register them with FFI
        FFI.setDynamicFunctions(
            version: resolve("version"),
            createRuntime: resolve("create_baml_runtime"),
            destroyRuntime: resolve("destroy_baml_runtime"),
            registerCallbacks: resolve("register_callbacks"),
            callFunction: resolve("call_function_from_c"),
            callFunctionStream: resolve("call_function_stream_from_c"),
            callFunctionParse: resolve("call_function_parse_from_c"),
            buildRequest: resolve("build_request_from_c"),
            cancelFunctionCall: resolve("cancel_function_call"),
            callObjectConstructor: resolve("call_object_constructor"),
            callObjectMethod: resolve("call_object_method"),
            freeBuffer: resolve("free_buffer")
        )
    }

    private func resolve<T>(_ name: String) -> T {
        guard let sym = dlsym(handle, name) else {
            fatalError("BamlSwift: Failed to resolve symbol '\(name)' from libbaml_cffi.dylib")
        }
        return unsafeBitCast(sym, to: T.self)
    }

    deinit {
        if let handle = handle {
            dlclose(handle)
        }
    }
}
#endif
