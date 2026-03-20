package com.boundaryml.baml;

/**
 * Thrown when the LLM response could not be parsed or validated against the
 * expected BAML schema. This corresponds to CFFI error messages that reference
 * schema or parse failures.
 */
public class BamlValidationError extends BamlException {
    public BamlValidationError(String message) {
        super(message);
    }

    public BamlValidationError(String message, Throwable cause) {
        super(message, cause);
    }
}
