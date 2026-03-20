package com.boundaryml.baml;

/**
 * Thrown when the upstream LLM provider returns a rate-limit response (HTTP 429
 * or a message containing "rate limit"). The retry policy in {@link BamlRuntime}
 * will automatically retry on this error when configured to do so.
 */
public class BamlRateLimitError extends BamlClientError {
    public BamlRateLimitError(String message) {
        super(message);
    }

    public BamlRateLimitError(String message, Throwable cause) {
        super(message, cause);
    }
}
