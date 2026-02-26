import Foundation
import BamlCFFI

/// Swift wrapper around the C `Buffer` struct returned by Rust FFI.
/// Automatically frees the buffer on deinit to prevent memory leaks.
internal final class FFIBuffer {
    let data: Data
    private let raw: BamlCFFI.Buffer

    init(_ buf: BamlCFFI.Buffer) {
        self.raw = buf
        if buf.ptr != nil && buf.len > 0 {
            self.data = Data(bytes: buf.ptr!, count: buf.len)
        } else {
            self.data = Data()
        }
    }

    deinit {
        #if os(macOS)
        FFI.freeBuffer(raw)
        #else
        free_buffer(raw)
        #endif
    }

    var isEmpty: Bool { data.isEmpty }
}
