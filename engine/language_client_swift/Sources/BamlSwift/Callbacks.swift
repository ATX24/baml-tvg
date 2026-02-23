import Foundation
import BamlCFFI

// Top-level functions that match BamlCallbackFn / BamlOnTickFn exactly.
// Swift can convert compatible global functions to C function pointers implicitly.
// These are registered with Rust via baml_register_callbacks() in loadBamlLibrary().

/// Rust calls this when a function call produces a result (or streaming chunk).
/// `ptr` + `len` are protobuf-encoded CFFIValueHolder bytes.
func bamlTriggerCallback(
    _ id: UInt32,
    _ isDone: Int32,
    _ ptr: UnsafePointer<Int8>?,
    _ len: UInt
) {
    guard let ptr, len > 0 else {
        if isDone != 0 { registryResume(id: id, data: Data()) }
        return
    }
    let data = Data(bytes: ptr, count: Int(len))
    // For non-streaming calls, isDone is always 1.
    // Streaming partial chunks (isDone==0) are ignored for now.
    if isDone != 0 {
        registryResume(id: id, data: data)
    }
}

/// Rust calls this when a function call fails.
/// `ptr` + `len` contain a UTF-8 error message.
func bamlErrorCallback(
    _ id: UInt32,
    _ isDone: Int32,
    _ ptr: UnsafePointer<Int8>?,
    _ len: UInt
) {
    let message: String
    if let ptr, len > 0 {
        message = String(bytes: UnsafeRawBufferPointer(start: ptr, count: Int(len)), encoding: .utf8)
            ?? "unknown error (non-UTF8)"
    } else {
        message = "unknown error (empty callback)"
    }
    registryFail(id: id, error: BamlError.functionCallFailed(message))
}

/// Rust calls this periodically during streaming / collector ticks.
func bamlOnTickCallback(_ id: UInt32) {
    // No-op for now. Extend later for streaming / collector support.
}
