package com.boundaryml.baml;

/**
 * Metadata associated with a completed BAML function call.
 *
 * <p>All fields are optional (may be {@code -1} / {@code null} when the underlying
 * CFFI layer does not expose them for a particular provider or call type).
 */
public final class BamlCallMetadata {

    /** Total tokens consumed by the call (prompt + completion), or {@code -1} if unknown. */
    private final long totalTokens;

    /** Prompt tokens only, or {@code -1} if unknown. */
    private final long promptTokens;

    /** Completion tokens only, or {@code -1} if unknown. */
    private final long completionTokens;

    /** Wall-clock latency of the complete call in milliseconds, or {@code -1} if unknown. */
    private final long latencyMs;

    /** Opaque trace / request identifier returned by the provider, or {@code null}. */
    private final String traceId;

    private BamlCallMetadata(
        long totalTokens,
        long promptTokens,
        long completionTokens,
        long latencyMs,
        String traceId
    ) {
        this.totalTokens = totalTokens;
        this.promptTokens = promptTokens;
        this.completionTokens = completionTokens;
        this.latencyMs = latencyMs;
        this.traceId = traceId;
    }

    /** Returns a metadata object with all fields marked as unknown ({@code -1} / {@code null}). */
    public static BamlCallMetadata unknown() {
        return new BamlCallMetadata(-1L, -1L, -1L, -1L, null);
    }

    public static Builder builder() {
        return new Builder();
    }

    public long getTotalTokens()      { return totalTokens; }
    public long getPromptTokens()     { return promptTokens; }
    public long getCompletionTokens() { return completionTokens; }
    public long getLatencyMs()        { return latencyMs; }
    public String getTraceId()        { return traceId; }

    @Override
    public String toString() {
        return "BamlCallMetadata{"
            + "totalTokens=" + totalTokens
            + ", promptTokens=" + promptTokens
            + ", completionTokens=" + completionTokens
            + ", latencyMs=" + latencyMs
            + ", traceId='" + traceId + '\''
            + '}';
    }

    public static final class Builder {
        private long totalTokens = -1L;
        private long promptTokens = -1L;
        private long completionTokens = -1L;
        private long latencyMs = -1L;
        private String traceId;

        public Builder totalTokens(long v)      { this.totalTokens = v;      return this; }
        public Builder promptTokens(long v)     { this.promptTokens = v;     return this; }
        public Builder completionTokens(long v) { this.completionTokens = v; return this; }
        public Builder latencyMs(long v)        { this.latencyMs = v;        return this; }
        public Builder traceId(String v)        { this.traceId = v;          return this; }

        public BamlCallMetadata build() {
            return new BamlCallMetadata(totalTokens, promptTokens, completionTokens, latencyMs, traceId);
        }
    }
}
