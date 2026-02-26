import Foundation
import SwiftProtobuf

// Private wrapper for JSON roundtrip in BamlDecoder.convert
private struct _BamlWrapper<T: Decodable>: Decodable { let _v: T }

/// Decodes protobuf CFFIValueHolder into native Swift types.
public enum BamlDecoder {

    /// Decode a CFFIValueHolder into a Swift value.
    /// Returns nil for null values.
    static func decode(_ holder: Baml_Cffi_V1_CFFIValueHolder) -> Any? {
        guard let value = holder.value else { return nil }

        switch value {
        case .nullValue:
            return nil
        case .stringValue(let s):
            return s
        case .intValue(let i):
            return i
        case .floatValue(let f):
            return f
        case .boolValue(let b):
            return b
        case .classValue(let cls):
            return decodeClass(cls)
        case .enumValue(let e):
            return decodeEnum(e)
        case .literalValue(let lit):
            return decodeLiteral(lit)
        case .objectValue:
            // Raw object handles are not decoded to Swift values
            return nil
        case .listValue(let list):
            return list.items.map { decode($0) }
        case .mapValue(let map):
            var dict: [String: Any?] = [:]
            for entry in map.entries {
                dict[entry.key] = decode(entry.value)
            }
            return dict
        case .unionVariantValue(let union):
            return decode(union.value)
        case .checkedValue(let checked):
            return decodeChecked(checked)
        case .streamingStateValue(let state):
            return decodeStreamState(state)
        }
    }

    /// Decode a class value into a dictionary.
    static func decodeClass(_ cls: Baml_Cffi_V1_CFFIValueClass) -> [String: Any?] {
        var fields: [String: Any?] = [:]
        for entry in cls.fields {
            fields[entry.key] = decode(entry.value)
        }
        return fields
    }

    /// Decode an enum value.
    static func decodeEnum(_ e: Baml_Cffi_V1_CFFIValueEnum) -> String {
        return e.value
    }

    /// Decode a literal value.
    private static func decodeLiteral(_ lit: Baml_Cffi_V1_CFFIFieldTypeLiteral) -> Any? {
        guard let literal = lit.literal else { return nil }
        switch literal {
        case .stringLiteral(let s): return s.value
        case .intLiteral(let i): return i.value
        case .boolLiteral(let b): return b.value
        }
    }

    /// Decode a checked value.
    static func decodeChecked(_ checked: Baml_Cffi_V1_CFFIValueChecked) -> Any? {
        // Returns a dictionary with value and checks
        var result: [String: Any] = [:]
        result["value"] = decode(checked.value)
        result["checks"] = checked.checks.map { check -> [String: Any] in
            var c: [String: Any] = [:]
            c["name"] = check.name
            c["expression"] = check.expression
            c["status"] = check.status
            return c
        }
        return result
    }

    /// Decode a streaming state value.
    static func decodeStreamState(_ state: Baml_Cffi_V1_CFFIValueStreamingState) -> Any? {
        var result: [String: Any] = [:]
        result["value"] = decode(state.value)
        result["state"] = state.state.rawValue
        return result
    }

    /// Decode raw protobuf bytes from a callback into a CFFIValueHolder.
    /// The callback data is a raw CFFIValueHolder — NOT wrapped in InvocationResponse.
    /// (InvocationResponse is only used for the synchronous return of call_function_from_c.)
    static func decodeResponse(_ data: Data) throws -> Baml_Cffi_V1_CFFIValueHolder {
        return try Baml_Cffi_V1_CFFIValueHolder(serializedBytes: data)
    }

    // MARK: - High-level typed decode helpers (for generated code)

    /// Convert an untyped BAML-decoded value to a concrete Decodable Swift type.
    ///
    /// Works for:
    /// - `String` (BAML string or enum variant name)
    /// - `Int64`, `Double`, `Bool`
    /// - Structs and enums that are `Codable` (generated BAML types)
    /// - Arrays and dictionaries of the above
    ///
    /// - Throws if the value cannot be converted.
    public static func convert<T: Decodable>(_ any: Any?) throws -> T {
        let wrapped: [String: Any] = ["_v": _toJSONObject(any)]
        let jsonData = try JSONSerialization.data(withJSONObject: wrapped)
        return try JSONDecoder().decode(_BamlWrapper<T>.self, from: jsonData)._v
    }

    /// Decode a raw `Data` result from `BamlRuntime.callFunction` into a typed Swift value.
    ///
    /// Use this in generated function implementations.
    public static func decodeResult<T: Decodable>(_ data: Data) throws -> T {
        let holder = try decodeResponse(data)
        let raw = decode(holder)
        return try convert(raw)
    }

    /// Decode a raw `Data` chunk from `BamlRuntime.callFunctionStream` into a `StreamState<T>`.
    ///
    /// Handles both `streamingStateValue`-wrapped chunks and plain-value chunks.
    public static func decodeStreamChunk<T: Sendable & Decodable>(_ data: Data) throws -> StreamState<T> {
        let holder = try decodeResponse(data)
        guard let value = holder.value else { return .pending }
        switch value {
        case .streamingStateValue(let state):
            let innerRaw = decode(state.value)
            switch state.state {
            case .started:
                return .started(try convert(innerRaw))
            case .done:
                return .done(try convert(innerRaw))
            default:
                return .pending
            }
        default:
            let raw = decode(holder)
            return .done(try convert(raw))
        }
    }

    // MARK: - Private helpers

    private static func _toJSONObject(_ value: Any?) -> Any {
        switch value {
        case nil:
            return NSNull()
        case let s as String:
            return s
        case let i as Int64:
            return NSNumber(value: i)
        case let i as Int:
            return NSNumber(value: i)
        case let d as Double:
            return NSNumber(value: d)
        case let f as Float:
            return NSNumber(value: f)
        case let b as Bool:
            return NSNumber(value: b)
        case let arr as [Any?]:
            return arr.map { _toJSONObject($0) }
        case let dict as [String: Any?]:
            var result: [String: Any] = [:]
            for (k, v) in dict { result[k] = _toJSONObject(v) }
            return result
        case let dict as [String: Any]:
            var result: [String: Any] = [:]
            for (k, v) in dict { result[k] = _toJSONObject(v) }
            return result
        default:
            return NSNull()
        }
    }
}
