package com.boundaryml.baml;

import com.boundaryml.baml.cffi.v1.HostClassValue;
import com.boundaryml.baml.cffi.v1.HostFunctionArguments;
import com.boundaryml.baml.cffi.v1.HostMapEntry;
import com.boundaryml.baml.cffi.v1.HostValue;
import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

class BamlEncoderTest {

    @Test
    void encodeArgs_primitivesAndCollections() throws Exception {
        Map<String, Object> kwargs = new LinkedHashMap<>();
        kwargs.put("s", "hello");
        kwargs.put("i", 42L);
        kwargs.put("f", 1.5);
        kwargs.put("b", true);
        kwargs.put("list", Arrays.asList(1, 2, 3));
        Map<String, Object> inner = new LinkedHashMap<>();
        inner.put("k", "v");
        kwargs.put("map", inner);

        byte[] bytes = BamlEncoder.encodeArgs(kwargs);
        HostFunctionArguments parsed = HostFunctionArguments.parseFrom(bytes);
        assertEquals(6, parsed.getKwargsCount());

        HostMapEntry sEntry = findKwarg(parsed, "s");
        assertEquals(HostValue.ValueCase.STRING_VALUE, sEntry.getValue().getValueCase());
        assertEquals("hello", sEntry.getValue().getStringValue());

        HostMapEntry iEntry = findKwarg(parsed, "i");
        assertEquals(HostValue.ValueCase.INT_VALUE, iEntry.getValue().getValueCase());
        assertEquals(42L, iEntry.getValue().getIntValue());

        HostMapEntry listEntry = findKwarg(parsed, "list");
        assertEquals(HostValue.ValueCase.LIST_VALUE, listEntry.getValue().getValueCase());
        List<HostValue> listValues = listEntry.getValue().getListValue().getValuesList();
        assertEquals(3, listValues.size());
        assertEquals(1L, listValues.get(0).getIntValue());
    }

    @Test
    void encodeValue_enumAndPojoProduceEnumAndClass() {
        // Enum via Java enum
        TestEnum e = TestEnum.FIRST;
        HostValue enumHost = BamlEncoder.encodeValue(e);
        assertEquals(HostValue.ValueCase.ENUM_VALUE, enumHost.getValueCase());
        assertEquals("TestEnum", enumHost.getEnumValue().getName());
        assertEquals("FIRST", enumHost.getEnumValue().getValue());

        // Class via explicit BamlClassValue
        Map<String, Object> fields = new LinkedHashMap<>();
        fields.put("name", "Ada");
        fields.put("age", 37L);
        BamlClassValue classValue = new BamlClassValue("Person", fields);
        HostValue classHost = BamlEncoder.encodeValue(classValue);
        assertEquals(HostValue.ValueCase.CLASS_VALUE, classHost.getValueCase());
        HostClassValue hv = classHost.getClassValue();
        assertEquals("Person", hv.getName());
        assertEquals(2, hv.getFieldsCount());
    }

    @Test
    void encodeValue_pojoFallsBackToClassValue() {
        Person p = new Person("Bob", 21);
        HostValue host = BamlEncoder.encodeValue(p);
        assertEquals(HostValue.ValueCase.CLASS_VALUE, host.getValueCase());
        HostClassValue hv = host.getClassValue();
        assertEquals("Person", hv.getName());
        // We expect at least the two declared fields to be present.
        assertTrue(hv.getFieldsCount() >= 2);
    }

    private static HostMapEntry findKwarg(HostFunctionArguments args, String key) {
        return args.getKwargsList()
            .stream()
            .filter(e -> key.equals(e.getStringKey()))
            .findFirst()
            .orElseThrow(() -> new AssertionError("Missing kwarg: " + key));
    }

    enum TestEnum {
        FIRST,
        SECOND
    }

    static class Person {
        private final String name;
        private final int age;

        Person(String name, int age) {
            this.name = name;
            this.age = age;
        }

        public String getName() {
            return name;
        }

        public int getAge() {
            return age;
        }
    }
}

