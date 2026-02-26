import Foundation

/// Errors that can occur when using BamlSwift.
public enum BamlError: Error, LocalizedError {
    case runtimeCreationFailed(String)
    case ffiError(String)
    case libraryNotFound(String)
    case libraryLoadFailed(String)
    case downloadFailed(String)
    case versionMismatch(expected: String, got: String)
    case encodingFailed(String)
    case decodingFailed(String)
    case callbackError(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .runtimeCreationFailed(let msg): return "BAML runtime creation failed: \(msg)"
        case .ffiError(let msg): return "BAML FFI error: \(msg)"
        case .libraryNotFound(let msg): return "BAML library not found: \(msg)"
        case .libraryLoadFailed(let msg): return "BAML library load failed: \(msg)"
        case .downloadFailed(let msg): return "BAML download failed: \(msg)"
        case .versionMismatch(let expected, let got):
            return "BAML version mismatch: expected \(expected), got \(got)"
        case .encodingFailed(let msg): return "BAML encoding failed: \(msg)"
        case .decodingFailed(let msg): return "BAML decoding failed: \(msg)"
        case .callbackError(let msg): return "BAML callback error: \(msg)"
        case .cancelled: return "BAML call was cancelled"
        }
    }
}
