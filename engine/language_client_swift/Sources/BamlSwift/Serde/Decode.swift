import Foundation

// Converts a CFFIValueHolder protobuf back into Swift native values.
// Mirrors engine/language_client_go/baml_go/serde/decode.go

/// Decode a CFFIValueHolder into a native Swift value.
/// Returns String, Int64, Double, Bool, [Any], [String: Any], or nil.
public func decode(_ holder: Baml_Cffi_V1_CFFIValueHolder) -> Any? {
    switch holder.value {
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

    case .listValue(let list):
        return list.items.map { decode($0) as Any }

    case .mapValue(let map):
        var result: [String: Any] = [:]
        for entry in map.entries {
            result[entry.key] = decode(entry.value) as Any
        }
        return result

    case .classValue(let cls):
        var result: [String: Any] = [:]
        for entry in cls.fields {
            result[entry.key] = decode(entry.value) as Any
        }
        return result

    case .enumValue(let e):
        return e.value

    case .literalValue(let lit):
        switch lit.literal {
        case .stringLiteral(let s): return s.value
        case .intLiteral(let i):    return i.value
        case .boolLiteral(let b):   return b.value
        case nil:                   return nil
        }

    case .unionVariantValue(let u):
        return decode(u.value)

    case .checkedValue(let c):
        return decode(c.value)

    case .streamingStateValue(let s):
        return decode(s.value)

    case .objectValue:
        return nil  // raw object handles not supported in hello world

    case nil:
        return nil
    }
}
