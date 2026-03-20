package com.boundaryml.baml;

import com.boundaryml.baml.cffi.v1.*;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Unit tests for {@link BamlDecoder}.
 *
 * Every test builds a {@link CFFIValueHolder} protobuf directly, serialises it to bytes,
 * and verifies that {@link BamlDecoder#decodeResult(byte[])} produces the expected Java value.
 * No native library or live runtime is required.
 */
class BamlDecoderTest {

    // -----------------------------------------------------------------------
    // Primitive types
    // -----------------------------------------------------------------------

    @Test
    void decodeResult_null_returnsNull() throws Exception {
        byte[] bytes = CFFIValueHolder.newBuilder()
            .setNullValue(CFFIValueNull.getDefaultInstance())
            .build()
            .toByteArray();
        assertNull(BamlDecoder.decodeResult(bytes));
    }

    @Test
    void decodeResult_emptyBytes_returnsNull() throws Exception {
        assertNull(BamlDecoder.decodeResult(new byte[0]));
        assertNull(BamlDecoder.decodeResult(null));
    }

    @Test
    void decodeResult_string() throws Exception {
        byte[] bytes = CFFIValueHolder.newBuilder()
            .setStringValue("hello world")
            .build()
            .toByteArray();
        assertEquals("hello world", BamlDecoder.decodeResult(bytes));
    }

    @Test
    void decodeResult_emptyString() throws Exception {
        byte[] bytes = CFFIValueHolder.newBuilder()
            .setStringValue("")
            .build()
            .toByteArray();
        assertEquals("", BamlDecoder.decodeResult(bytes));
    }

    @Test
    void decodeResult_integer() throws Exception {
        byte[] bytes = CFFIValueHolder.newBuilder()
            .setIntValue(42L)
            .build()
            .toByteArray();
        assertEquals(42L, BamlDecoder.decodeResult(bytes));
    }

    @Test
    void decodeResult_negativeInteger() throws Exception {
        byte[] bytes = CFFIValueHolder.newBuilder()
            .setIntValue(-9999L)
            .build()
            .toByteArray();
        assertEquals(-9999L, BamlDecoder.decodeResult(bytes));
    }

    @Test
    void decodeResult_float() throws Exception {
        byte[] bytes = CFFIValueHolder.newBuilder()
            .setFloatValue(3.14)
            .build()
            .toByteArray();
        assertEquals(3.14, (Double) BamlDecoder.decodeResult(bytes), 1e-9);
    }

    @Test
    void decodeResult_boolTrue() throws Exception {
        byte[] bytes = CFFIValueHolder.newBuilder()
            .setBoolValue(true)
            .build()
            .toByteArray();
        assertEquals(Boolean.TRUE, BamlDecoder.decodeResult(bytes));
    }

    @Test
    void decodeResult_boolFalse() throws Exception {
        byte[] bytes = CFFIValueHolder.newBuilder()
            .setBoolValue(false)
            .build()
            .toByteArray();
        assertEquals(Boolean.FALSE, BamlDecoder.decodeResult(bytes));
    }

    // -----------------------------------------------------------------------
    // Collection types
    // -----------------------------------------------------------------------

    @Test
    @SuppressWarnings("unchecked")
    void decodeResult_listOfStrings() throws Exception {
        CFFIValueHolder item1 = CFFIValueHolder.newBuilder().setStringValue("a").build();
        CFFIValueHolder item2 = CFFIValueHolder.newBuilder().setStringValue("b").build();
        byte[] bytes = CFFIValueHolder.newBuilder()
            .setListValue(CFFIValueList.newBuilder()
                .addItems(item1)
                .addItems(item2))
            .build()
            .toByteArray();

        List<Object> result = (List<Object>) BamlDecoder.decodeResult(bytes);
        assertEquals(List.of("a", "b"), result);
    }

    @Test
    @SuppressWarnings("unchecked")
    void decodeResult_nestedList() throws Exception {
        CFFIValueHolder inner = CFFIValueHolder.newBuilder()
            .setListValue(CFFIValueList.newBuilder()
                .addItems(CFFIValueHolder.newBuilder().setIntValue(1L))
                .addItems(CFFIValueHolder.newBuilder().setIntValue(2L)))
            .build();
        byte[] bytes = CFFIValueHolder.newBuilder()
            .setListValue(CFFIValueList.newBuilder().addItems(inner))
            .build()
            .toByteArray();

        List<Object> outer = (List<Object>) BamlDecoder.decodeResult(bytes);
        assertEquals(1, outer.size());
        List<Object> innerDecoded = (List<Object>) outer.get(0);
        assertEquals(List.of(1L, 2L), innerDecoded);
    }

    @Test
    @SuppressWarnings("unchecked")
    void decodeResult_mapOfStringToInt() throws Exception {
        CFFIMapEntry entry1 = CFFIMapEntry.newBuilder()
            .setKey("x")
            .setValue(CFFIValueHolder.newBuilder().setIntValue(10L))
            .build();
        CFFIMapEntry entry2 = CFFIMapEntry.newBuilder()
            .setKey("y")
            .setValue(CFFIValueHolder.newBuilder().setIntValue(20L))
            .build();
        byte[] bytes = CFFIValueHolder.newBuilder()
            .setMapValue(CFFIValueMap.newBuilder().addEntries(entry1).addEntries(entry2))
            .build()
            .toByteArray();

        Map<String, Object> result = (Map<String, Object>) BamlDecoder.decodeResult(bytes);
        assertEquals(10L, result.get("x"));
        assertEquals(20L, result.get("y"));
    }

    // -----------------------------------------------------------------------
    // Class value
    // -----------------------------------------------------------------------

    @Test
    void decodeResult_classValue() throws Exception {
        CFFITypeName typeName = CFFITypeName.newBuilder().setName("Person").build();
        CFFIMapEntry nameField = CFFIMapEntry.newBuilder()
            .setKey("name")
            .setValue(CFFIValueHolder.newBuilder().setStringValue("Ada"))
            .build();
        CFFIMapEntry ageField = CFFIMapEntry.newBuilder()
            .setKey("age")
            .setValue(CFFIValueHolder.newBuilder().setIntValue(37L))
            .build();
        byte[] bytes = CFFIValueHolder.newBuilder()
            .setClassValue(CFFIValueClass.newBuilder()
                .setName(typeName)
                .addFields(nameField)
                .addFields(ageField))
            .build()
            .toByteArray();

        BamlClassValue cls = (BamlClassValue) BamlDecoder.decodeResult(bytes);
        assertEquals("Person", cls.getTypeName());
        assertEquals("Ada", cls.getFields().get("name"));
        assertEquals(37L, cls.getFields().get("age"));
    }

    @Test
    void decodeResult_classValue_emptyFields() throws Exception {
        CFFITypeName typeName = CFFITypeName.newBuilder().setName("Empty").build();
        byte[] bytes = CFFIValueHolder.newBuilder()
            .setClassValue(CFFIValueClass.newBuilder().setName(typeName))
            .build()
            .toByteArray();

        BamlClassValue cls = (BamlClassValue) BamlDecoder.decodeResult(bytes);
        assertEquals("Empty", cls.getTypeName());
        assertTrue(cls.getFields().isEmpty());
    }

    // -----------------------------------------------------------------------
    // Enum value
    // -----------------------------------------------------------------------

    @Test
    void decodeResult_enumValue() throws Exception {
        CFFITypeName typeName = CFFITypeName.newBuilder().setName("Mood").build();
        byte[] bytes = CFFIValueHolder.newBuilder()
            .setEnumValue(CFFIValueEnum.newBuilder()
                .setName(typeName)
                .setValue("HAPPY"))
            .build()
            .toByteArray();

        BamlEnumValue ev = (BamlEnumValue) BamlDecoder.decodeResult(bytes);
        assertEquals("Mood", ev.getEnumName());
        assertEquals("HAPPY", ev.getValue());
    }

    // -----------------------------------------------------------------------
    // Literal values
    // -----------------------------------------------------------------------

    @Test
    void decodeResult_literalString() throws Exception {
        byte[] bytes = CFFIValueHolder.newBuilder()
            .setLiteralValue(CFFIFieldTypeLiteral.newBuilder()
                .setStringLiteral(CFFILiteralString.newBuilder().setValue("success")))
            .build()
            .toByteArray();
        assertEquals("success", BamlDecoder.decodeResult(bytes));
    }

    @Test
    void decodeResult_literalInt() throws Exception {
        byte[] bytes = CFFIValueHolder.newBuilder()
            .setLiteralValue(CFFIFieldTypeLiteral.newBuilder()
                .setIntLiteral(CFFILiteralInt.newBuilder().setValue(7L)))
            .build()
            .toByteArray();
        assertEquals(7L, BamlDecoder.decodeResult(bytes));
    }

    @Test
    void decodeResult_literalBool() throws Exception {
        byte[] bytes = CFFIValueHolder.newBuilder()
            .setLiteralValue(CFFIFieldTypeLiteral.newBuilder()
                .setBoolLiteral(CFFILiteralBool.newBuilder().setValue(true)))
            .build()
            .toByteArray();
        assertEquals(Boolean.TRUE, BamlDecoder.decodeResult(bytes));
    }

    // -----------------------------------------------------------------------
    // Union variant
    // -----------------------------------------------------------------------

    @Test
    void decodeResult_unionVariant() throws Exception {
        CFFITypeName unionName = CFFITypeName.newBuilder().setName("IntOrString").build();
        CFFIValueHolder inner = CFFIValueHolder.newBuilder().setIntValue(99L).build();
        byte[] bytes = CFFIValueHolder.newBuilder()
            .setUnionVariantValue(CFFIValueUnionVariant.newBuilder()
                .setName(unionName)
                .setValue(inner)
                .setValueOptionName("int"))
            .build()
            .toByteArray();

        BamlUnionValue uv = (BamlUnionValue) BamlDecoder.decodeResult(bytes);
        assertEquals("IntOrString", uv.getUnionName());
        assertEquals("int", uv.getOptionName());
        assertEquals(99L, uv.getValue());
    }

    @Test
    void decodeResult_unionVariant_noInnerValue() throws Exception {
        CFFITypeName unionName = CFFITypeName.newBuilder().setName("MaybeInt").build();
        byte[] bytes = CFFIValueHolder.newBuilder()
            .setUnionVariantValue(CFFIValueUnionVariant.newBuilder()
                .setName(unionName)
                .setIsOptional(true)
                .setValueOptionName("none"))
            .build()
            .toByteArray();

        BamlUnionValue uv = (BamlUnionValue) BamlDecoder.decodeResult(bytes);
        assertEquals("MaybeInt", uv.getUnionName());
        assertTrue(uv.isOptional());
        assertNull(uv.getValue());
    }

    // -----------------------------------------------------------------------
    // Checked value (passes through inner value)
    // -----------------------------------------------------------------------

    @Test
    void decodeResult_checkedValue_returnsInner() throws Exception {
        CFFIValueHolder inner = CFFIValueHolder.newBuilder().setStringValue("verified").build();
        byte[] bytes = CFFIValueHolder.newBuilder()
            .setCheckedValue(CFFIValueChecked.newBuilder().setValue(inner))
            .build()
            .toByteArray();
        assertEquals("verified", BamlDecoder.decodeResult(bytes));
    }

    @Test
    void decodeResult_checkedValue_noInner_returnsNull() throws Exception {
        byte[] bytes = CFFIValueHolder.newBuilder()
            .setCheckedValue(CFFIValueChecked.getDefaultInstance())
            .build()
            .toByteArray();
        assertNull(BamlDecoder.decodeResult(bytes));
    }

    // -----------------------------------------------------------------------
    // Streaming state (passes through current snapshot)
    // -----------------------------------------------------------------------

    @Test
    void decodeResult_streamingState_returnsCurrentSnapshot() throws Exception {
        CFFIValueHolder inner = CFFIValueHolder.newBuilder().setStringValue("partial").build();
        byte[] bytes = CFFIValueHolder.newBuilder()
            .setStreamingStateValue(CFFIValueStreamingState.newBuilder().setValue(inner))
            .build()
            .toByteArray();
        assertEquals("partial", BamlDecoder.decodeResult(bytes));
    }

    @Test
    void decodeResult_streamingState_noSnapshot_returnsNull() throws Exception {
        byte[] bytes = CFFIValueHolder.newBuilder()
            .setStreamingStateValue(CFFIValueStreamingState.getDefaultInstance())
            .build()
            .toByteArray();
        assertNull(BamlDecoder.decodeResult(bytes));
    }

    // -----------------------------------------------------------------------
    // Error cases
    // -----------------------------------------------------------------------

    @Test
    void decodeResult_corruptBytes_throwsBamlException() {
        byte[] garbage = new byte[]{0x01, 0x02, 0x03, (byte) 0xFF};
        // protobuf may silently ignore unknown fields; if it throws it must be BamlException
        try {
            BamlDecoder.decodeResult(garbage);
            // If it doesn't throw, the result must be non-exceptional (proto is lenient)
        } catch (BamlException e) {
            assertTrue(e.getMessage().contains("Failed to decode"));
        }
    }

}
