import Foundation
import BamlCFFI

// Converts Swift values into the protobuf types that Rust expects.
// Mirrors the logic in engine/language_client_go/baml_go/serde/encode.go

/// Build a HostFunctionArguments from a simple kwargs dictionary.
/// Supports: String, Int, Double, Bool, [Any], [String: Any], nil.
public func encodeArgs(
    kwargs: [String: Any],
    envVars: [String: String] = [:]
) throws -> Baml_Cffi_V1_HostFunctionArguments {
    var args = Baml_Cffi_V1_HostFunctionArguments()
    args.kwargs = try encodeMapEntries(kwargs)
    args.env = envVars.map { key, val in
        var e = Baml_Cffi_V1_HostEnvVar()
        e.key   = key
        e.value = val
        return e
    }
    return args
}

// MARK: - Internal helpers

func encodeMapEntries(_ dict: [String: Any]) throws -> [Baml_Cffi_V1_HostMapEntry] {
    try dict.map { key, val in
        var entry = Baml_Cffi_V1_HostMapEntry()
        entry.stringKey = key
        entry.value     = try encodeValue(val)
        return entry
    }
}

func encodeValue(_ value: Any) throws -> Baml_Cffi_V1_HostValue {
    var v = Baml_Cffi_V1_HostValue()
    switch value {
    case let s as String:
        v.stringValue = s
    case let i as Int:
        v.intValue = Int64(i)
    case let i as Int64:
        v.intValue = i
    case let f as Double:
        v.floatValue = f
    case let f as Float:
        v.floatValue = Double(f)
    case let b as Bool:
        v.boolValue = b
    case let arr as [Any]:
        var list = Baml_Cffi_V1_HostListValue()
        list.values = try arr.map { try encodeValue($0) }
        v.listValue = list
    case let dict as [String: Any]:
        var map = Baml_Cffi_V1_HostMapValue()
        map.entries = try encodeMapEntries(dict)
        v.mapValue = map
    case Optional<Any>.none:
        break  // leave value unset — proto3 treats missing oneof as null
    default:
        throw BamlError.decodingFailed("Cannot encode value of type \(type(of: value))")
    }
    return v
}
