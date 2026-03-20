package com.boundaryml.baml;

/**
 * Thrown when a BAML function call (blocking or streaming) exceeds the
 * configured timeout. Corresponds to CFFI error messages containing "timeout".
 */
public class BamlTimeoutError extends BamlClientError {
    public BamlTimeoutError(String message) {
        super(message);
    }

    public BamlTimeoutError(String message, Throwable cause) {
        super(message, cause);
    }
}
