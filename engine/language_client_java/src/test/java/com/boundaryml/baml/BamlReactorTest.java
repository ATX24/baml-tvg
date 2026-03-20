package com.boundaryml.baml;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import reactor.test.StepVerifier;

import java.util.Collections;

import static org.junit.jupiter.api.Assertions.assertEquals;

class BamlReactorTest {

    @BeforeEach
    void setUp() {
        BamlRuntime.setCffiForTests(new BamlRuntimeTest.StubCFFI());
    }

    @Test
    void toFlux_emitsPartialsAndCompletes() {
        BamlRuntime runtime = BamlRuntime.create("root", "{}", "{}");
        byte[] encoded = BamlEncoder.encodeArgs(Collections.emptyMap());

        BamlStream<String, String> stream = runtime.callFunctionStream(
            "stream",
            encoded,
            bytes -> (String) BamlDecoder.decodeResult(bytes),
            bytes -> (String) BamlDecoder.decodeResult(bytes)
        );

        StepVerifier.create(BamlReactor.toFlux(stream))
            .expectNext("chunk1")
            .expectNext("chunk2")
            .expectComplete()
            .verify();
    }

    @Test
    void toFlux_finalResultStillAvailableFromStream() throws Exception {
        BamlRuntime runtime = BamlRuntime.create("root", "{}", "{}");
        byte[] encoded = BamlEncoder.encodeArgs(Collections.emptyMap());

        BamlStream<String, String> stream = runtime.callFunctionStream(
            "stream",
            encoded,
            bytes -> (String) BamlDecoder.decodeResult(bytes),
            bytes -> (String) BamlDecoder.decodeResult(bytes)
        );

        java.util.List<String> partials = BamlReactor.toFlux(stream).collectList().block();
        assertEquals(java.util.List.of("chunk1", "chunk2"), partials);

        String finalResult = stream.getFinalResult();
        assertEquals("final:stream", finalResult);
    }
}
