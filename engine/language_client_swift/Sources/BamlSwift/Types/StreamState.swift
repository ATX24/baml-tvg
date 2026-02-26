import Foundation

/// Streaming state for partial results, mirroring Go's StreamState[T] type.
public enum StreamState<T: Sendable>: Sendable {
    case pending
    case started(T)
    case done(T)
}
