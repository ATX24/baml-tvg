import Foundation
import SwiftProtobuf

/// Encodes Swift values into protobuf HostValue for sending to the BAML runtime.
public enum BamlEncoder {

    /// Encode a class value.
    static func encodeClass(
        name: String, fields: [String: Any], dynamicFields: [String: Any]? = nil
    ) throws -> Baml_Cffi_V1_HostValue {
        var classValue = Baml_Cffi_V1_HostClassValue()
        classValue.name = name
        for (key, value) in fields {
            var entry = Baml_Cffi_V1_HostMapEntry()
            entry.key = .stringKey(key)
            entry.value = try encodeValue(value)
            classValue.fields.append(entry)
        }
        if let dynamicFields = dynamicFields {
            for (key, value) in dynamicFields {
                var entry = Baml_Cffi_V1_HostMapEntry()
                entry.key = .stringKey(key)
                entry.value = try encodeValue(value)
                classValue.fields.append(entry)
            }
        }
        var hostValue = Baml_Cffi_V1_HostValue()
        hostValue.value = .classValue(classValue)
        return hostValue
    }

    /// Encode an enum value.
    static func encodeEnum(
        name: String, value: String
    ) -> Baml_Cffi_V1_HostValue {
        var enumValue = Baml_Cffi_V1_HostEnumValue()
        enumValue.name = name
        enumValue.value = value
        var hostValue = Baml_Cffi_V1_HostValue()
        hostValue.value = .enumValue(enumValue)
        return hostValue
    }

    /// Encode an arbitrary Swift value into a HostValue.
    static func encodeValue(_ value: Any) throws -> Baml_Cffi_V1_HostValue {
        var hostValue = Baml_Cffi_V1_HostValue()

        switch value {
        case let s as String:
            hostValue.value = .stringValue(s)
        case let i as Int:
            hostValue.value = .intValue(Int64(i))
        case let i as Int64:
            hostValue.value = .intValue(i)
        case let d as Double:
            hostValue.value = .floatValue(d)
        case let b as Bool:
            hostValue.value = .boolValue(b)
        case is NSNull:
            // Null = missing value field (no explicit null in HostValue)
            break
        case let arr as [Any]:
            var list = Baml_Cffi_V1_HostListValue()
            list.values = try arr.map { try encodeValue($0) }
            hostValue.value = .listValue(list)
        case let dict as [String: Any]:
            var map = Baml_Cffi_V1_HostMapValue()
            for (k, v) in dict {
                var entry = Baml_Cffi_V1_HostMapEntry()
                entry.key = .stringKey(k)
                entry.value = try encodeValue(v)
                map.entries.append(entry)
            }
            hostValue.value = .mapValue(map)
        case let hv as Baml_Cffi_V1_HostValue:
            return hv
        default:
            throw BamlError.encodingFailed("Unsupported type: \(type(of: value))")
        }

        return hostValue
    }

    /// Encode function arguments into serialized protobuf bytes for FFI.
    /// This is the public overload used by generated code.
    public static func encodeFunctionArgs(
        kwargs: [String: Any],
        envVars: [String: String] = [:]
    ) throws -> Data {
        return try encodeFunctionArgs(kwargs: kwargs, envVars: envVars, clientRegistry: nil)
    }

    /// Encode function arguments into serialized protobuf bytes for FFI.
    /// Internal overload that also accepts a dynamic client registry.
    static func encodeFunctionArgs(
        kwargs: [String: Any],
        envVars: [String: String] = [:],
        clientRegistry: Baml_Cffi_V1_HostClientRegistry? = nil
    ) throws -> Data {
        var args = Baml_Cffi_V1_HostFunctionArguments()
        for (key, value) in kwargs {
            var entry = Baml_Cffi_V1_HostMapEntry()
            entry.key = .stringKey(key)
            entry.value = try encodeValue(value)
            args.kwargs.append(entry)
        }
        for (key, value) in envVars {
            var env = Baml_Cffi_V1_HostEnvVar()
            env.key = key
            env.value = value
            args.env.append(env)
        }
        if let registry = clientRegistry {
            args.clientRegistry = registry
        }
        return try args.serializedData()
    }
}
