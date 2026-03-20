package com.boundaryml.baml;

/**
 * Wraps a decoded BAML function result together with call metadata (token usage,
 * latency, trace id).
 *
 * <p>The standard generated {@code Functions.java} returns the raw value directly.
 * Use {@link BamlRuntime#callFunctionParseWithMetadata} when you need both the
 * value and the associated metadata.
 *
 * @param <T> the decoded return type of the BAML function
 */
public final class BamlResponse<T> {

    private final T value;
    private final BamlCallMetadata metadata;

    public BamlResponse(T value, BamlCallMetadata metadata) {
        this.value = value;
        this.metadata = metadata != null ? metadata : BamlCallMetadata.unknown();
    }

    /** The decoded function return value. */
    public T getValue() {
        return value;
    }

    /** Metadata about the call (tokens, latency, trace id). */
    public BamlCallMetadata getMetadata() {
        return metadata;
    }

    @Override
    public String toString() {
        return "BamlResponse{value=" + value + ", metadata=" + metadata + '}';
    }
}
