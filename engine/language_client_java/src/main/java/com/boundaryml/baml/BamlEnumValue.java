package com.boundaryml.baml;

/**
 * Simple representation of a BAML enum value on the Java side.
 *
 * This mirrors {@code HostEnumValue} / {@code CFFIValueEnum} but avoids
 * exposing protobuf types directly in the public API.
 */
public final class BamlEnumValue {

    private final String enumName;
    private final String value;

    public BamlEnumValue(String enumName, String value) {
        this.enumName = enumName != null ? enumName : "";
        this.value = value != null ? value : "";
    }

    /**
     * Name of the BAML enum type.
     */
    public String getEnumName() {
        return enumName;
    }

    /**
     * The concrete enum variant name.
     */
    public String getValue() {
        return value;
    }
}

