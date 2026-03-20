package com.boundaryml.baml;

import com.boundaryml.baml.cffi.v1.CFFIValueHolder;
import com.boundaryml.baml.cffi.v1.InvocationResponse;
import com.boundaryml.baml.cffi.v1.InvocationResponseSuccess;
import com.sun.jna.Memory;
import com.sun.jna.Pointer;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.*;

import static org.junit.jupiter.api.Assertions.*;

class BamlRuntimeTest {

    private StubCFFI stub;

    @BeforeEach
    void setUp() {
        stub = new StubCFFI();
        BamlRuntime.setCffiForTests(stub);
    }

    @Test
    void callFunctionParse_successfulRoundTrip() throws Exception {
        BamlRuntime runtime = BamlRuntime.create("root", "{}", "{}");
        byte[] encoded = BamlEncoder.encodeArgs(Collections.emptyMap());

        byte[] resultBytes = runtime.callFunctionParse("Echo", encoded);
        Object decoded = BamlDecoder.decodeResult(resultBytes);

        assertEquals("ok:Echo", decoded);
        assertEquals(1, stub.callCount);
    }

    @Test
    void callFunctionParse_propagatesImmediateError() {
        BamlRuntime runtime = BamlRuntime.create("root", "{}", "{}");
        byte[] encoded = BamlEncoder.encodeArgs(Collections.emptyMap());

        BamlException ex = assertThrows(
            BamlException.class,
            () -> runtime.callFunctionParse("fail", encoded)
        );
        assertTrue(ex.getMessage().contains("synthetic failure"));
        assertEquals(1, stub.callCount);
    }

    @Test
    void callFunctionParse_retriesOnTimeoutLikeError() throws Exception {
        stub.failFirst = true;

        BamlRuntime.BamlRuntimeOptions options = BamlRuntime.BamlRuntimeOptions
            .builder()
            .retryPolicy(BamlRuntime.RetryPolicy.exponentialBackoff(
                3,
                java.time.Duration.ofSeconds(10),
                0,
                1.0
            ))
            .build();

        BamlRuntime runtime = BamlRuntime.create("root", "{}", "{}", options);
        byte[] encoded = BamlEncoder.encodeArgs(Collections.emptyMap());

        byte[] resultBytes = runtime.callFunctionParse("timeout_once", encoded);
        Object decoded = BamlDecoder.decodeResult(resultBytes);

        assertEquals("ok:timeout_once", decoded);
        assertEquals(2, stub.callCount);
    }

    @Test
    void callFunctionParse_handlesConcurrentCalls() throws Exception {
        BamlRuntime runtime = BamlRuntime.create("root", "{}", "{}");
        byte[] encoded = BamlEncoder.encodeArgs(Collections.emptyMap());

        ExecutorService executor = Executors.newFixedThreadPool(4);
        try {
            List<Callable<String>> tasks = Arrays.asList(
                () -> (String) BamlDecoder.decodeResult(runtime.callFunctionParse("f1", encoded)),
                () -> (String) BamlDecoder.decodeResult(runtime.callFunctionParse("f2", encoded)),
                () -> (String) BamlDecoder.decodeResult(runtime.callFunctionParse("f3", encoded)),
                () -> (String) BamlDecoder.decodeResult(runtime.callFunctionParse("f4", encoded))
            );

            List<Future<String>> futures = executor.invokeAll(tasks);
            assertEquals("ok:f1", futures.get(0).get(5, TimeUnit.SECONDS));
            assertEquals("ok:f2", futures.get(1).get(5, TimeUnit.SECONDS));
            assertEquals("ok:f3", futures.get(2).get(5, TimeUnit.SECONDS));
            assertEquals("ok:f4", futures.get(3).get(5, TimeUnit.SECONDS));
            assertEquals(4, stub.callCount);
        } finally {
            executor.shutdownNow();
        }
    }

    @Test
    void callFunctionParseAsync_returnsResult() throws Exception {
        BamlRuntime runtime = BamlRuntime.create("root", "{}", "{}");
        byte[] encoded = BamlEncoder.encodeArgs(Collections.emptyMap());

        CompletableFuture<byte[]> future = runtime.callFunctionParseAsync("Echo", encoded);
        assertNotNull(future, "callFunctionParseAsync must return a non-null future");

        byte[] resultBytes = future.get(10, TimeUnit.SECONDS);
        Object decoded = BamlDecoder.decodeResult(resultBytes);
        assertEquals("ok:Echo", decoded);
    }

    @Test
    void callFunctionParseAsync_propagatesError() {
        BamlRuntime runtime = BamlRuntime.create("root", "{}", "{}");
        byte[] encoded = BamlEncoder.encodeArgs(Collections.emptyMap());

        CompletableFuture<byte[]> future = runtime.callFunctionParseAsync("fail", encoded);

        ExecutionException ex = assertThrows(
            ExecutionException.class,
            () -> future.get(10, TimeUnit.SECONDS)
        );
        assertInstanceOf(BamlException.class, ex.getCause());
        assertTrue(ex.getCause().getMessage().contains("synthetic failure"));
    }

    @Test
    void callFunctionParseAsync_handlesConcurrentCalls() throws Exception {
        BamlRuntime runtime = BamlRuntime.create("root", "{}", "{}");
        byte[] encoded = BamlEncoder.encodeArgs(Collections.emptyMap());

        CompletableFuture<byte[]> f1 = runtime.callFunctionParseAsync("a1", encoded);
        CompletableFuture<byte[]> f2 = runtime.callFunctionParseAsync("a2", encoded);
        CompletableFuture<byte[]> f3 = runtime.callFunctionParseAsync("a3", encoded);

        CompletableFuture.allOf(f1, f2, f3).get(15, TimeUnit.SECONDS);

        assertEquals("ok:a1", BamlDecoder.decodeResult(f1.get()));
        assertEquals("ok:a2", BamlDecoder.decodeResult(f2.get()));
        assertEquals("ok:a3", BamlDecoder.decodeResult(f3.get()));
        assertEquals(3, stub.callCount);
    }

    @Test
    void callFunctionStream_basicStreamingFlow() throws Exception {
        BamlRuntime runtime = BamlRuntime.create("root", "{}", "{}");
        byte[] encoded = BamlEncoder.encodeArgs(Collections.emptyMap());

        BamlStream<String, String> stream = runtime.callFunctionStream(
            "stream",
            encoded,
            bytes -> (String) BamlDecoder.decodeResult(bytes),
            bytes -> (String) BamlDecoder.decodeResult(bytes)
        );

        // Collect streaming events.
        java.util.List<String> chunks = new java.util.ArrayList<>();
        for (String value : stream) {
            chunks.add(value);
        }

        assertEquals(Arrays.asList("chunk1", "chunk2"), chunks);

        String finalDecoded = stream.getFinalResult();
        assertEquals("final:stream", finalDecoded);
    }

    /**
     * Simple CFFI stub that simulates the behaviour the runtime expects:
     * - {@code call_function_from_c} returns an InvocationResponse and also
     *   triggers the result callback with a CFFIValueHolder payload.
     * - {@code call_function_stream_from_c} returns an InvocationResponse and
     *   triggers multiple result callbacks for streaming events.
     */
    static final class StubCFFI implements BamlRuntime.BamlCFFI {
        BamlRuntime.ResultCallbackFn resultCb;
        BamlRuntime.ResultCallbackFn errorCb;
        BamlRuntime.OnTickCallbackFn onTickCb;

        int callCount = 0;
        boolean failFirst = false;

        @Override
        public void register_callbacks(
            BamlRuntime.ResultCallbackFn resultCb,
            BamlRuntime.ResultCallbackFn errorCb,
            BamlRuntime.OnTickCallbackFn onTickCb
        ) {
            this.resultCb = resultCb;
            this.errorCb = errorCb;
            this.onTickCb = onTickCb;
        }

        @Override
        public Pointer create_baml_runtime(String rootPath, String srcFilesJson, String envVarsJson) {
            // Any non-null pointer is fine for tests.
            return Pointer.createConstant(1);
        }

        @Override
        public void destroy_baml_runtime(Pointer runtime) {
            // no-op for tests
        }

        @Override
        public BamlRuntime.Buffer call_function_from_c(
            Pointer runtime,
            String functionName,
            byte[] encodedArgs,
            long length,
            int id
        ) {
            callCount++;

            ensureCallbacksInitialized();

            if ("fail".equals(functionName)
                || (failFirst && callCount == 1 && "timeout_once".equals(functionName))) {
                // Immediate error via InvocationResponse.error; no callback.
                InvocationResponse resp = InvocationResponse.newBuilder()
                    .setError("synthetic failure: timeout")
                    .build();
                return bufferFromBytes(resp.toByteArray());
            }

            // Success path: schedule a single result via callback and return success response.
            String payload = "ok:" + functionName;
            CFFIValueHolder holder = CFFIValueHolder.newBuilder()
                .setStringValue(payload)
                .build();
            byte[] valueBytes = holder.toByteArray();
            Pointer valuePtr = new Memory(valueBytes.length);
            valuePtr.write(0, valueBytes, 0, valueBytes.length);

            // Simulate async completion but it's safe to invoke synchronously here.
            resultCb.callback(id, 1, valuePtr, valueBytes.length);

            InvocationResponse resp = InvocationResponse.newBuilder()
                .setSuccess(InvocationResponseSuccess.getDefaultInstance())
                .build();
            return bufferFromBytes(resp.toByteArray());
        }

        @Override
        public BamlRuntime.Buffer call_function_stream_from_c(
            Pointer runtime,
            String functionName,
            byte[] encodedArgs,
            long length,
            int id
        ) {
            callCount++;

            ensureCallbacksInitialized();

            // Two chunks followed by a final snapshot.
            CFFIValueHolder chunk1 = CFFIValueHolder.newBuilder()
                .setStringValue("chunk1")
                .build();
            CFFIValueHolder chunk2 = CFFIValueHolder.newBuilder()
                .setStringValue("chunk2")
                .build();
            CFFIValueHolder finalHolder = CFFIValueHolder.newBuilder()
                .setStringValue("final:" + functionName)
                .build();

            sendResult(id, 0, chunk1);
            sendResult(id, 0, chunk2);
            sendResult(id, 1, finalHolder);

            InvocationResponse resp = InvocationResponse.newBuilder()
                .setSuccess(InvocationResponseSuccess.getDefaultInstance())
                .build();
            return bufferFromBytes(resp.toByteArray());
        }

        @Override
        public void free_buffer(BamlRuntime.Buffer buffer) {
            // Memory will be GC'd; nothing to do for tests.
        }

        @Override
        public BamlRuntime.Buffer version() {
            byte[] bytes = "test-version".getBytes(java.nio.charset.StandardCharsets.UTF_8);
            return bufferFromBytes(bytes);
        }

        private void sendResult(int id, int isDone, CFFIValueHolder holder) {
            ensureCallbacksInitialized();
            byte[] bytes = holder.toByteArray();
            Pointer ptr = new Memory(bytes.length);
            ptr.write(0, bytes, 0, bytes.length);
            resultCb.callback(id, isDone, ptr, bytes.length);
        }

        private static BamlRuntime.Buffer bufferFromBytes(byte[] bytes) {
            Pointer ptr = new Memory(bytes.length);
            ptr.write(0, bytes, 0, bytes.length);
            BamlRuntime.Buffer buf = new BamlRuntime.Buffer();
            buf.ptr = ptr;
            buf.len = bytes.length;
            return buf;
        }

        private void ensureCallbacksInitialized() {
            if (resultCb != null) {
                return;
            }
            // In some test setups the runtime may have already registered its
            // callbacks before this stub saw them. Fall back to reflecting the
            // static field so tests remain robust.
            try {
                java.lang.reflect.Field f =
                    BamlRuntime.class.getDeclaredField("RESULT_CALLBACK");
                f.setAccessible(true);
                this.resultCb = (BamlRuntime.ResultCallbackFn) f.get(null);
            } catch (Exception e) {
                throw new RuntimeException("Failed to initialize test callbacks", e);
            }
        }
    }
}

