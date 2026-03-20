package com.boundaryml.baml;

import com.boundaryml.baml.cffi.v1.HostClassValue;
import com.boundaryml.baml.cffi.v1.HostClientProperty;
import com.boundaryml.baml.cffi.v1.HostClientRegistry;
import com.boundaryml.baml.cffi.v1.HostEnumValue;
import com.boundaryml.baml.cffi.v1.HostEnvVar;
import com.boundaryml.baml.cffi.v1.HostFunctionArguments;
import com.boundaryml.baml.cffi.v1.HostListValue;
import com.boundaryml.baml.cffi.v1.HostMapEntry;
import com.boundaryml.baml.cffi.v1.HostMapValue;
import com.boundaryml.baml.cffi.v1.HostValue;

import java.lang.reflect.Array;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Encodes BAML function arguments to protobuf (HostFunctionArguments).
 *
 * This encoder is intentionally generic and can represent all BAML value
 * shapes that the Rust runtime understands:
 *
 * - Primitives: String, integral numbers, floating-point numbers, boolean.
 * - Collections: java.util.List / arrays (as HostListValue),
 *   java.util.Map with String keys (as HostMapValue).
 * - Enums: any {@link java.lang.Enum} or {@link BamlEnumValue}
 *   (as HostEnumValue).
 * - Classes/records/POJOs: {@link BamlClassValue} or arbitrary objects with
 *   JavaBean-style getters (as HostClassValue).
 *
 * More advanced BAML concepts (unions, checked values, streaming handles)
 * are represented via their underlying encoded values and higher-level
 * semantics are handled on the Rust side.
 */
public final class BamlEncoder {

    private BamlEncoder() {}

    /**
     * Generic encoder for function kwargs. Supported value types mirror
     * {@link #encodeValue(Object)}.
     */
    public static byte[] encodeArgs(Map<String, Object> kwargs) {
        return encodeArgs(kwargs, null);
    }

    /**
     * Encodes function kwargs together with an optional {@link BamlClientRegistry}
     * override. When {@code registry} is non-null its clients are serialized into
     * {@code HostFunctionArguments.client_registry}, allowing per-call LLM client
     * overrides without changing the static {@code .baml} configuration.
     *
     * <p>Environment variables from {@link System#getenv()} are always included so
     * the Rust runtime can resolve {@code env.VAR_NAME} references (e.g.
     * {@code api_key env.OPENAI_API_KEY}) in {@code .baml} client declarations.
     */
    public static byte[] encodeArgs(Map<String, Object> kwargs, BamlClientRegistry registry) {
        HostFunctionArguments.Builder argsBuilder = HostFunctionArguments.newBuilder();
        if (kwargs != null) {
            for (Map.Entry<String, Object> entry : kwargs.entrySet()) {
                String key = entry.getKey();
                HostValue value = encodeValue(entry.getValue());
                HostMapEntry mapEntry = HostMapEntry.newBuilder()
                    .setStringKey(key)
                    .setValue(value)
                    .build();
                argsBuilder.addKwargs(mapEntry);
            }
        }
        if (registry != null) {
            argsBuilder.setClientRegistry(encodeClientRegistry(registry));
        }
        // Pass environment variables with every call so the native BAML runtime can
        // resolve env.VAR_NAME references (e.g. api_key env.OPENAI_API_KEY) declared
        // in .baml client blocks.  The Rust call_function_from_c reads env_vars from
        // the encoded HostFunctionArguments.env field — NOT from create_baml_runtime.
        for (Map.Entry<String, String> envEntry : System.getenv().entrySet()) {
            argsBuilder.addEnv(
                HostEnvVar.newBuilder()
                    .setKey(envEntry.getKey())
                    .setValue(envEntry.getValue())
                    .build()
            );
        }
        return argsBuilder.build().toByteArray();
    }

    private static HostClientRegistry encodeClientRegistry(BamlClientRegistry registry) {
        HostClientRegistry.Builder rb = HostClientRegistry.newBuilder();
        if (registry.getPrimary() != null) {
            rb.setPrimary(registry.getPrimary());
        }
        for (BamlClientOptions client : registry.getClients()) {
            HostClientProperty.Builder cpb = HostClientProperty.newBuilder()
                .setName(client.getName())
                .setProvider(client.getProvider());
            if (client.getRetryPolicy() != null) {
                cpb.setRetryPolicy(client.getRetryPolicy());
            }
            for (Map.Entry<String, Object> opt : client.getOptions().entrySet()) {
                HostMapEntry optEntry = HostMapEntry.newBuilder()
                    .setStringKey(opt.getKey())
                    .setValue(encodeValue(opt.getValue()))
                    .build();
                cpb.addOptions(optEntry);
            }
            rb.addClients(cpb.build());
        }
        return rb.build();
    }

    /**
     * Encode a single Java value into a HostValue tree.
     *
     * The mapping is:
     * - null → HostValue with no oneof set (treated as null in Rust)
     * - String → string_value
     * - Integer/Long/Short/Byte → int_value (int64)
     * - Float/Double → float_value (double)
     * - Boolean → bool_value
     * - java.util.List / arrays → list_value (recursive)
     * - java.util.Map with String keys → map_value (recursive)
     * - java.lang.Enum / BamlEnumValue → enum_value
     * - BamlClassValue / arbitrary POJO with getters → class_value
     *
     * Anything else falls back to String via toString().
     */
    public static HostValue encodeValue(Object value) {
        HostValue.Builder builder = HostValue.newBuilder();

        if (value == null) {
            // Leave oneof unset; interpreted as null on the Rust side.
            return builder.build();
        }

        if (value instanceof String) {
            builder.setStringValue((String) value);
            return builder.build();
        }

        if (value instanceof Integer
            || value instanceof Long
            || value instanceof Short
            || value instanceof Byte) {
            long v = ((Number) value).longValue();
            builder.setIntValue(v);
            return builder.build();
        }

        if (value instanceof Float || value instanceof Double) {
            double v = ((Number) value).doubleValue();
            builder.setFloatValue(v);
            return builder.build();
        }

        if (value instanceof Boolean) {
            builder.setBoolValue((Boolean) value);
            return builder.build();
        }

        // Treat any array (primitive or object) as a list.
        if (value.getClass().isArray()) {
            int length = Array.getLength(value);
            List<Object> asList = new ArrayList<>(length);
            for (int i = 0; i < length; i++) {
                asList.add(Array.get(value, i));
            }
            return encodeValue(asList);
        }

        if (value instanceof List<?>) {
            HostListValue.Builder listBuilder = HostListValue.newBuilder();
            for (Object item : (List<?>) value) {
                listBuilder.addValues(encodeValue(item));
            }
            builder.setListValue(listBuilder.build());
            return builder.build();
        }

        if (value instanceof Map<?, ?>) {
            HostMapValue.Builder mapBuilder = HostMapValue.newBuilder();
            for (Map.Entry<?, ?> e : ((Map<?, ?>) value).entrySet()) {
                Object rawKey = e.getKey();
                if (!(rawKey instanceof String)) {
                    throw new IllegalArgumentException(
                        "Only String keys are supported in BAML HostMapValue; got: "
                            + (rawKey == null ? "null" : rawKey.getClass().getName())
                    );
                }
                String key = (String) rawKey;
                HostValue encodedValue = encodeValue(e.getValue());
                HostMapEntry mapEntry = HostMapEntry.newBuilder()
                    .setStringKey(key)
                    .setValue(encodedValue)
                    .build();
                mapBuilder.addEntries(mapEntry);
            }
            builder.setMapValue(mapBuilder.build());
            return builder.build();
        }

        // Dedicated wrapper types.
        if (value instanceof BamlEnumValue) {
            BamlEnumValue v = (BamlEnumValue) value;
            HostEnumValue enumValue = HostEnumValue.newBuilder()
                .setName(v.getEnumName())
                .setValue(v.getValue())
                .build();
            builder.setEnumValue(enumValue);
            return builder.build();
        }

        if (value instanceof Enum<?>) {
            Enum<?> e = (Enum<?>) value;
            HostEnumValue enumValue = HostEnumValue.newBuilder()
                .setName(e.getDeclaringClass().getSimpleName())
                .setValue(e.name())
                .build();
            builder.setEnumValue(enumValue);
            return builder.build();
        }

        if (value instanceof BamlClassValue) {
            BamlClassValue c = (BamlClassValue) value;
            HostClassValue.Builder classBuilder = HostClassValue.newBuilder()
                .setName(c.getTypeName());
            for (Map.Entry<String, Object> field : c.getFields().entrySet()) {
                HostMapEntry mapEntry = HostMapEntry.newBuilder()
                    .setStringKey(field.getKey())
                    .setValue(encodeValue(field.getValue()))
                    .build();
                classBuilder.addFields(mapEntry);
            }
            builder.setClassValue(classBuilder.build());
            return builder.build();
        }

        // Fallback: attempt to encode arbitrary POJOs as class_value based on getters.
        HostClassValue.Builder classBuilder = HostClassValue.newBuilder()
            .setName(value.getClass().getSimpleName());
        boolean hasFields = false;

        for (Method method : value.getClass().getMethods()) {
            if (!Modifier.isPublic(method.getModifiers()) || method.getParameterCount() != 0) {
                continue;
            }
            String methodName = method.getName();
            if (methodName.equals("getClass")) {
                continue;
            }

            String fieldName = null;
            if (methodName.startsWith("get") && methodName.length() > 3) {
                fieldName = Character.toLowerCase(methodName.charAt(3)) + methodName.substring(4);
            } else if (methodName.startsWith("is")
                && methodName.length() > 2
                && (method.getReturnType() == boolean.class || method.getReturnType() == Boolean.class)) {
                fieldName = Character.toLowerCase(methodName.charAt(2)) + methodName.substring(3);
            }

            if (fieldName == null || fieldName.isEmpty()) {
                continue;
            }

            Object fieldValue;
            try {
                fieldValue = method.invoke(value);
            } catch (Exception ignored) {
                continue;
            }

            HostMapEntry mapEntry = HostMapEntry.newBuilder()
                .setStringKey(fieldName)
                .setValue(encodeValue(fieldValue))
                .build();
            classBuilder.addFields(mapEntry);
            hasFields = true;
        }

        if (hasFields) {
            builder.setClassValue(classBuilder.build());
            return builder.build();
        }

        // Final fallback: encode as string.
        builder.setStringValue(String.valueOf(value));
        return builder.build();
    }
}
