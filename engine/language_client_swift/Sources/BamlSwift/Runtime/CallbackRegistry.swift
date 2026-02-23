import Foundation

/// Bridges Rust's C callbacks → Swift async/await.
///
/// When a BAML function is called, we:
///   1. Generate a unique UInt32 ID
///   2. Store a CheckedContinuation keyed by that ID
///   3. Pass the ID to Rust's call_function_from_c
///   4. When Rust calls trigger_callback(id, ...) we resume the continuation
///
/// Thread safety: the dictionary is protected by NSLock since callbacks arrive
/// from an unknown Rust/Tokio thread. CheckedContinuation.resume() is safe to
/// call from any thread.

private let registryLock = NSLock()
private var pendingContinuations: [UInt32: CheckedContinuation<Data, Error>] = [:]

func registryStore(id: UInt32, continuation: CheckedContinuation<Data, Error>) {
    registryLock.lock()
    pendingContinuations[id] = continuation
    registryLock.unlock()
}

func registryResume(id: UInt32, data: Data) {
    registryLock.lock()
    let cont = pendingContinuations.removeValue(forKey: id)
    registryLock.unlock()
    cont?.resume(returning: data)
}

func registryFail(id: UInt32, error: Error) {
    registryLock.lock()
    let cont = pendingContinuations.removeValue(forKey: id)
    registryLock.unlock()
    cont?.resume(throwing: error)
}

func registryNextID() -> UInt32 {
    // Simple random ID; retry on collision
    registryLock.lock()
    defer { registryLock.unlock() }
    var id: UInt32
    repeat {
        id = UInt32.random(in: 1..<1_000_000)
    } while pendingContinuations[id] != nil
    return id
}
