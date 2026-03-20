package com.boundaryml.baml;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Objects;

/**
 * Runtime override for the set of LLM clients used in a BAML function call,
 * mirroring the {@code HostClientRegistry} proto message.
 *
 * <p>Pass a registry to {@link BamlEncoder#encodeArgs(java.util.Map, BamlClientRegistry)}
 * to override the statically declared clients in your {@code .baml} files:
 *
 * <pre>{@code
 * BamlClientRegistry registry = BamlClientRegistry.builder()
 *     .primary("MyFastClient")
 *     .client(BamlClientOptions.builder("MyFastClient")
 *         .provider("openai")
 *         .option("model", "gpt-4o-mini")
 *         .option("api_key", System.getenv("OPENAI_API_KEY"))
 *         .build())
 *     .build();
 *
 * byte[] encoded = BamlEncoder.encodeArgs(kwargs, registry);
 * byte[] result = runtime.callFunctionParse("MyFunction", encoded);
 * }</pre>
 */
public final class BamlClientRegistry {

    private final String primary;
    private final List<BamlClientOptions> clients;

    private BamlClientRegistry(Builder builder) {
        this.primary = builder.primary;
        this.clients = Collections.unmodifiableList(new ArrayList<>(builder.clients));
    }

    /** The name of the primary client to use for this call, or {@code null} to use the default. */
    public String getPrimary() { return primary; }

    /** The list of client overrides. */
    public List<BamlClientOptions> getClients() { return clients; }

    public static Builder builder() { return new Builder(); }

    /** Returns an empty registry (no overrides). */
    public static BamlClientRegistry empty() {
        return builder().build();
    }

    public static final class Builder {
        private String primary;
        private final List<BamlClientOptions> clients = new ArrayList<>();

        public Builder primary(String primary) {
            this.primary = Objects.requireNonNull(primary, "primary");
            return this;
        }

        public Builder client(BamlClientOptions client) {
            this.clients.add(Objects.requireNonNull(client, "client"));
            return this;
        }

        public Builder clients(List<BamlClientOptions> clients) {
            this.clients.addAll(Objects.requireNonNull(clients, "clients"));
            return this;
        }

        public BamlClientRegistry build() {
            return new BamlClientRegistry(this);
        }
    }
}
