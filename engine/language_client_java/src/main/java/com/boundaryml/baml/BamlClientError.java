package com.boundaryml.baml;

/**
 * Base class for client-related errors (HTTP errors, timeouts, etc.)
 * that occur while calling BAML functions.
 */
public class BamlClientError extends BamlException {
    public BamlClientError(String message) {
        super(message);
    }

    public BamlClientError(String message, Throwable cause) {
        super(message, cause);
    }
}

