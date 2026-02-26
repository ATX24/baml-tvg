import Foundation
import BamlCFFI

// MARK: - Callback result types

internal enum CallbackResult {
    case value(data: Data, isDone: Bool)
    case error(String)
}

// MARK: - Callback registry

/// Thread-safe registry mapping callback IDs to Swift continuations.
/// Bridges C function pointer callbacks from Rust into Swift async/await.
internal final class CallbackRegistry: @unchecked Sendable {
    static let shared = CallbackRegistry()

    private let lock = NSLock()
    private var nextId: UInt32 = 1
    private var singleCallbacks: [UInt32: CheckedContinuation<Data, Error>] = [:]
    private var streamCallbacks: [UInt32: AsyncThrowingStream<Data, Error>.Continuation] = [:]

    private init() {}

    /// Generate a unique callback ID
    func generateId() -> UInt32 {
        lock.lock()
        defer { lock.unlock() }
        let id = nextId
        nextId &+= 1
        return id
    }

    // MARK: - Single call (non-streaming)

    func registerSingle(id: UInt32, continuation: CheckedContinuation<Data, Error>) {
        lock.lock()
        defer { lock.unlock() }
        singleCallbacks[id] = continuation
    }

    func cancelSingle(id: UInt32) {
        lock.lock()
        let cont = singleCallbacks.removeValue(forKey: id)
        lock.unlock()
        cont?.resume(throwing: BamlError.cancelled)
    }

    // MARK: - Streaming call

    func registerStream(id: UInt32, continuation: AsyncThrowingStream<Data, Error>.Continuation) {
        lock.lock()
        defer { lock.unlock() }
        streamCallbacks[id] = continuation
    }

    // MARK: - Dispatch from C callbacks

    func dispatchResult(id: UInt32, isDone: Bool, data: Data) {
        lock.lock()

        // Check if it's a single callback
        if isDone, let cont = singleCallbacks.removeValue(forKey: id) {
            lock.unlock()
            cont.resume(returning: data)
            return
        }

        // Check if it's a stream callback
        if let cont = streamCallbacks[id] {
            if isDone {
                streamCallbacks.removeValue(forKey: id)
                lock.unlock()
                // For streaming, the final callback contains the complete result
                cont.yield(data)
                cont.finish()
            } else {
                lock.unlock()
                cont.yield(data)
            }
            return
        }

        lock.unlock()
    }

    func dispatchError(id: UInt32, message: String) {
        lock.lock()

        if let cont = singleCallbacks.removeValue(forKey: id) {
            lock.unlock()
            cont.resume(throwing: BamlError.callbackError(message))
            return
        }

        if let cont = streamCallbacks.removeValue(forKey: id) {
            streamCallbacks.removeValue(forKey: id)
            lock.unlock()
            cont.finish(throwing: BamlError.callbackError(message))
            return
        }

        lock.unlock()
    }

    func dispatchTick(id: UInt32) {
        // Tick events can be used for keep-alive or progress tracking
        // Currently no-op — the streaming data arrives via dispatchResult
    }
}

// MARK: - Global C-compatible callback functions

// These are registered with the Rust runtime via register_callbacks().
// They MUST be global functions (not closures) for @convention(c) compatibility.
// Called from arbitrary Tokio threads in the Rust runtime.

/// Called when a function call completes with a result.
/// Signature must match: void (*)(uint32_t, int32_t, const int8_t*, uintptr_t)
private func triggerCallback(
    callId: UInt32, isDone: Int32,
    content: UnsafePointer<Int8>?, length: UInt
) {
    let data: Data
    if let content = content, length > 0 {
        data = Data(bytes: content, count: Int(length))
    } else {
        data = Data()
    }
    CallbackRegistry.shared.dispatchResult(
        id: callId, isDone: isDone != 0, data: data
    )
}

/// Called when a function call fails with an error.
/// Signature must match: void (*)(uint32_t, int32_t, const int8_t*, uintptr_t)
private func errorCallback(
    callId: UInt32, isDone: Int32,
    content: UnsafePointer<Int8>?, length: UInt
) {
    let message: String
    if let content = content, length > 0 {
        message = String(
            bytes: Data(bytes: content, count: Int(length)),
            encoding: .utf8
        ) ?? "Unknown BAML error"
    } else {
        message = "Unknown BAML error (empty)"
    }
    CallbackRegistry.shared.dispatchError(id: callId, message: message)
}

/// Called for tick events during streaming.
/// Signature must match: void (*)(uint32_t)
private func onTickCallback(callId: UInt32) {
    CallbackRegistry.shared.dispatchTick(id: callId)
}

// MARK: - Callback function pointers (for registration)

/// Get the C-compatible function pointers for callback registration.
/// These match the `CallbackFn` and `OnTickCallbackFn` typedefs from the C header.
internal enum CallbackPointers {
    static let trigger: CallbackFn = triggerCallback
    static let error: CallbackFn = errorCallback
    static let onTick: OnTickCallbackFn = onTickCallback
}
