package com.boundaryml.baml;

public class BamlException extends RuntimeException {
    public BamlException(String message) {
        super(message);
    }

    public BamlException(String message, Throwable cause) {
        super(message, cause);
    }
}
