package com.boundaryml.baml;

import com.boundaryml.baml.cffi.v1.CFFIFieldTypeLiteral;
import com.boundaryml.baml.cffi.v1.CFFIMapEntry;
import com.boundaryml.baml.cffi.v1.CFFIValueChecked;
import com.boundaryml.baml.cffi.v1.CFFIValueClass;
import com.boundaryml.baml.cffi.v1.CFFIValueEnum;
import com.boundaryml.baml.cffi.v1.CFFIValueHolder;
import com.boundaryml.baml.cffi.v1.CFFIValueStreamingState;
import com.boundaryml.baml.cffi.v1.CFFIValueUnionVariant;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Decodes BAML function results from protobuf ({@link CFFIValueHolder}).
 *
 * This class now understands all outbound BAML value shapes and maps them
 * into Java primitives, collections, or small helper types in this package
 * ({@link BamlClassValue}, {@link BamlEnumValue}, {@link BamlUnionValue}).
 *
 * Callers that need full access to the raw protobuf messages can always
 * bypass this and parse {@link CFFIValueHolder} directly.
 */
public final class BamlDecoder {

    private BamlDecoder() {}

    /**
     * Generic result decoder that maps the {@link CFFIValueHolder} tree into
     * a Java object using reasonable defaults:
     *
     * - STRING_VALUE → String
     * - INT_VALUE → Long
     * - FLOAT_VALUE → Double
     * - BOOL_VALUE → Boolean
     * - NULL_VALUE → null
     * - LIST_VALUE → java.util.List<Object> (recursive)
     * - MAP_VALUE → java.util.Map<String, Object> (recursive)
     * - CLASS_VALUE → {@link BamlClassValue}
     * - ENUM_VALUE → {@link BamlEnumValue}
     * - LITERAL_VALUE → String / Long / Boolean (depending on literal)
     * - UNION_VARIANT_VALUE → {@link BamlUnionValue}
     * - CHECKED_VALUE → decodes to the inner value and ignores checks for now
     * - STREAMING_STATE_VALUE → decodes to the inner value (current snapshot)
     */
    public static Object decodeResult(byte[] response) throws BamlException {
        if (response == null || response.length == 0) {
            return null;
        }
        try {
            CFFIValueHolder holder = CFFIValueHolder.parseFrom(response);
            return decodeValue(holder);
        } catch (Exception e) {
            if (e instanceof BamlException) throw (BamlException) e;
            throw new BamlException("Failed to decode result: " + e.getMessage(), e);
        }
    }

    private static Object decodeValue(CFFIValueHolder holder) throws BamlException {
        switch (holder.getValueCase()) {
            case STRING_VALUE:
                return holder.getStringValue();
            case INT_VALUE:
                return holder.getIntValue();
            case FLOAT_VALUE:
                return holder.getFloatValue();
            case BOOL_VALUE:
                return holder.getBoolValue();
            case NULL_VALUE:
                return null;
            case LIST_VALUE: {
                List<Object> list = new ArrayList<>();
                for (CFFIValueHolder item : holder.getListValue().getItemsList()) {
                    list.add(decodeValue(item));
                }
                return list;
            }
            case MAP_VALUE: {
                Map<String, Object> map = new LinkedHashMap<>();
                for (CFFIMapEntry entry : holder.getMapValue().getEntriesList()) {
                    String key = entry.getKey();
                    Object value = decodeValue(entry.getValue());
                    map.put(key, value);
                }
                return map;
            }
            case CLASS_VALUE: {
                CFFIValueClass cls = holder.getClassValue();
                Map<String, Object> fields = new LinkedHashMap<>();
                for (CFFIMapEntry entry : cls.getFieldsList()) {
                    fields.put(entry.getKey(), decodeValue(entry.getValue()));
                }
                return new BamlClassValue(cls.getName().getName(), fields);
            }
            case ENUM_VALUE: {
                CFFIValueEnum ev = holder.getEnumValue();
                return new BamlEnumValue(ev.getName().getName(), ev.getValue());
            }
            case LITERAL_VALUE: {
                CFFIFieldTypeLiteral lit = holder.getLiteralValue();
                switch (lit.getLiteralCase()) {
                    case STRING_LITERAL:
                        return lit.getStringLiteral().getValue();
                    case INT_LITERAL:
                        return lit.getIntLiteral().getValue();
                    case BOOL_LITERAL:
                        return lit.getBoolLiteral().getValue();
                    case LITERAL_NOT_SET:
                    default:
                        return null;
                }
            }
            case OBJECT_VALUE:
                // Raw object/handle; expose the underlying protobuf for advanced callers.
                return holder.getObjectValue();
            case UNION_VARIANT_VALUE: {
                CFFIValueUnionVariant uv = holder.getUnionVariantValue();
                Object inner = uv.hasValue() ? decodeValue(uv.getValue()) : null;
                String unionName = uv.hasName() ? uv.getName().getName() : "";
                String optionName = uv.getValueOptionName();
                return new BamlUnionValue(unionName, optionName, uv.getIsOptional(), uv.getIsSinglePattern(), inner);
            }
            case CHECKED_VALUE: {
                CFFIValueChecked checked = holder.getCheckedValue();
                // For now, surface the inner decoded value; callers that care
                // about individual checks can inspect the protobuf directly.
                if (checked.hasValue()) {
                    return decodeValue(checked.getValue());
                }
                return null;
            }
            case STREAMING_STATE_VALUE: {
                CFFIValueStreamingState state = holder.getStreamingStateValue();
                // Expose the current value snapshot if present; callers that
                // care about state machine details can inspect the protobuf.
                if (state.hasValue()) {
                    return decodeValue(state.getValue());
                }
                return null;
            }
            case VALUE_NOT_SET:
            default:
                throw new BamlException("Unsupported or unexpected result type: " + holder.getValueCase());
        }
    }
}

