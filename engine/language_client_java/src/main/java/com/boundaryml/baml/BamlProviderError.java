package com.boundaryml.baml;

/**
 * Thrown when the upstream LLM provider returns an unexpected HTTP error that
 * is not specifically a timeout or rate-limit. The {@link #getStatusCode()} may
 * be {@code -1} when the HTTP status is not available.
 */
public class BamlProviderError extends BamlClientError {
    private final int statusCode;

    public BamlProviderError(String message, int statusCode) {
        super(message);
        this.statusCode = statusCode;
    }

    public BamlProviderError(String message, int statusCode, Throwable cause) {
        super(message, cause);
        this.statusCode = statusCode;
    }

    /** The HTTP status code from the provider, or {@code -1} if unavailable. */
    public int getStatusCode() {
        return statusCode;
    }
}
