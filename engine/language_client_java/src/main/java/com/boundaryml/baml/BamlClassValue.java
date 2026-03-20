package com.boundaryml.baml;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Simple representation of a BAML class (struct) value on the Java side.
 *
 * This mirrors {@code HostClassValue} / {@code CFFIValueClass} but uses
 * regular Java collections and is convenient to work with in user code.
 */
public final class BamlClassValue {

    private final String typeName;
    private final Map<String, Object> fields;

    public BamlClassValue(String typeName, Map<String, Object> fields) {
        this.typeName = typeName != null ? typeName : "";
        if (fields == null || fields.isEmpty()) {
            this.fields = Collections.emptyMap();
        } else {
            this.fields = Collections.unmodifiableMap(new LinkedHashMap<>(fields));
        }
    }

    /**
     * Name of the BAML class/type, typically the same as in the schema.
     */
    public String getTypeName() {
        return typeName;
    }

    /**
     * Immutable map of field names to decoded values.
     */
    public Map<String, Object> getFields() {
        return fields;
    }
}

