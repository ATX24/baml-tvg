import Foundation
import BamlCFFI

// BamlBuffer, BamlCallbackFn, and BamlOnTickFn are imported from the BamlCFFI
// C target (Sources/BamlCFFI/include/BamlCFFI.h).
//
// Keeping them in C lets Swift use them in @convention(c) function types,
// which is not possible with Swift-defined structs.

extension BamlBuffer {
    /// Read buffer contents into Data. Does NOT free the buffer.
    func toData() -> Data? {
        guard let ptr, len > 0 else { return nil }
        return Data(bytes: ptr, count: len)
    }
}

/// Read the buffer contents into Data, then free it. Returns nil for empty buffers.
func readAndFreeBuffer(_ buf: BamlBuffer) -> Data? {
    defer { if buf.ptr != nil { baml_free_buffer(buf) } }
    return buf.toData()
}
