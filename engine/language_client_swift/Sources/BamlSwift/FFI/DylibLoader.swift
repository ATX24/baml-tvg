import Darwin
import Foundation
import BamlCFFI

/// Load libbaml_cffi from the given path, store all function pointers in the
/// C wrapper layer, and register Swift callbacks with Rust.
/// Must be called once before creating a BamlRuntime.
public func loadBamlLibrary(path: String) throws {
    guard let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else {
        let err = dlerror().map { String(cString: $0) } ?? "unknown error"
        throw BamlError.libraryLoadFailed("dlopen(\(path)): \(err)")
    }

    // Look up a symbol and pass its raw pointer to the C-layer setter.
    func load(_ rustName: String, setter: (UnsafeMutableRawPointer?) -> Void) throws {
        dlerror()  // clear previous error
        guard let ptr = dlsym(handle, rustName) else {
            let err = dlerror().map { String(cString: $0) } ?? "symbol not found"
            throw BamlError.symbolNotFound("\(rustName): \(err)")
        }
        setter(ptr)
    }

    try load("version",                  setter: baml_set_version)
    try load("create_baml_runtime",      setter: baml_set_create_runtime)
    try load("destroy_baml_runtime",     setter: baml_set_destroy_runtime)
    try load("register_callbacks",       setter: baml_set_register_callbacks)
    try load("call_function_from_c",     setter: baml_set_call_function)
    try load("call_function_stream_from_c", setter: baml_set_call_function_stream)
    try load("free_buffer",              setter: baml_set_free_buffer)
    try load("cancel_function_call",     setter: baml_set_cancel_function_call)

    // Register our Swift callbacks so Rust knows where to deliver results
    baml_register_callbacks(bamlTriggerCallback, bamlErrorCallback, bamlOnTickCallback)
}

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

public enum BamlError: Error, CustomStringConvertible {
    case libraryLoadFailed(String)
    case symbolNotFound(String)
    case runtimeCreationFailed
    case functionCallFailed(String)
    case decodingFailed(String)

    public var description: String {
        switch self {
        case .libraryLoadFailed(let s):  return "Failed to load BAML library: \(s)"
        case .symbolNotFound(let s):     return "Symbol not found in BAML library: \(s)"
        case .runtimeCreationFailed:     return "create_baml_runtime returned nil"
        case .functionCallFailed(let s): return "BAML function call failed: \(s)"
        case .decodingFailed(let s):     return "Failed to decode BAML response: \(s)"
        }
    }
}
