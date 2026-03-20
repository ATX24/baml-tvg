package com.boundaryml.baml;

/**
 * Representation of a union value decoded from {@code CFFIValueUnionVariant}.
 *
 * This keeps the union's logical name, the selected option name, and the
 * decoded Java value for that option.
 */
public final class BamlUnionValue {

    private final String unionName;
    private final String optionName;
    private final boolean optional;
    private final boolean singlePattern;
    private final Object value;

    public BamlUnionValue(String unionName, String optionName, boolean optional, boolean singlePattern, Object value) {
        this.unionName = unionName != null ? unionName : "";
        this.optionName = optionName != null ? optionName : "";
        this.optional = optional;
        this.singlePattern = singlePattern;
        this.value = value;
    }

    public String getUnionName() {
        return unionName;
    }

    public String getOptionName() {
        return optionName;
    }

    public boolean isOptional() {
        return optional;
    }

    public boolean isSinglePattern() {
        return singlePattern;
    }

    public Object getValue() {
        return value;
    }
}

