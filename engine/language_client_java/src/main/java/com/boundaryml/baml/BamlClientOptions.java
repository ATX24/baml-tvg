package com.boundaryml.baml;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Objects;

/**
 * Configuration for a single named LLM client override, mirroring the
 * {@code HostClientProperty} proto message.
 *
 * <pre>{@code
 * BamlClientOptions fast = BamlClientOptions.builder("MyFastClient")
 *     .provider("openai")
 *     .option("model", "gpt-4o-mini")
 *     .option("api_key", System.getenv("OPENAI_API_KEY"))
 *     .build();
 * }</pre>
 */
public final class BamlClientOptions {

    private final String name;
    private final String provider;
    private final String retryPolicy;
    private final Map<String, Object> options;

    private BamlClientOptions(Builder builder) {
        this.name = Objects.requireNonNull(builder.name, "name");
        this.provider = Objects.requireNonNull(builder.provider, "provider");
        this.retryPolicy = builder.retryPolicy;
        this.options = Collections.unmodifiableMap(new LinkedHashMap<>(builder.options));
    }

    public String getName()        { return name; }
    public String getProvider()    { return provider; }
    public String getRetryPolicy() { return retryPolicy; }
    public Map<String, Object> getOptions() { return options; }

    public static Builder builder(String name) {
        return new Builder(name);
    }

    public static final class Builder {
        private final String name;
        private String provider;
        private String retryPolicy;
        private final Map<String, Object> options = new LinkedHashMap<>();

        private Builder(String name) {
            this.name = Objects.requireNonNull(name, "name");
        }

        public Builder provider(String provider) {
            this.provider = provider;
            return this;
        }

        public Builder retryPolicy(String retryPolicy) {
            this.retryPolicy = retryPolicy;
            return this;
        }

        public Builder option(String key, Object value) {
            this.options.put(key, value);
            return this;
        }

        public Builder options(Map<String, Object> options) {
            this.options.putAll(options);
            return this;
        }

        public BamlClientOptions build() {
            return new BamlClientOptions(this);
        }
    }
}
