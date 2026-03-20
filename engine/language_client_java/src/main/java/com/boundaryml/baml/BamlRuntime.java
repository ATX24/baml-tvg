package com.boundaryml.baml;

import com.sun.jna.Callback;
import com.sun.jna.Library;
import com.sun.jna.Native;
import com.sun.jna.Pointer;
import com.sun.jna.Structure;

import java.lang.ref.Cleaner;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Function;

import com.boundaryml.baml.cffi.v1.InvocationResponse;

/**
 * BAML Runtime for Java using JNA to call libbaml_cffi.
 * Supports both blocking (parse) and streaming function calls, with optional retry.
 */
public class BamlRuntime {
    private final Pointer runtimePtr;
    private final BamlRuntimeOptions options;

    private static volatile BamlCFFI cffi;
    private static volatile String cffiLoadError;
    private static final AtomicInteger nextCallId = new AtomicInteger(1);

    /** Dedicated daemon thread pool for async BAML calls; avoids saturating the common fork-join pool. */
    private static final AtomicInteger THREAD_COUNTER = new AtomicInteger(1);
    private static final ExecutorService ASYNC_EXECUTOR = Executors.newCachedThreadPool(r -> {
        Thread t = new Thread(r, "baml-async-" + THREAD_COUNTER.getAndIncrement());
        t.setDaemon(true);
        return t;
    });

    /** Cleaner used to release native runtime pointers when instances are GC'd. */
    private static final Cleaner CLEANER = Cleaner.create();
    private final Cleaner.Cleanable cleanable;

    /** Pending non-streaming calls: id → future for the final result bytes. */
    private static final ConcurrentHashMap<Integer, CompletableFuture<byte[]>> pendingCalls =
        new ConcurrentHashMap<>();

    /** Pending streaming calls: id → StreamState managing the event queue and final future. */
    private static final ConcurrentHashMap<Integer, StreamState> pendingStreams =
        new ConcurrentHashMap<>();

    private static volatile boolean callbacksRegistered = false;
    private static final Object callbackLock = new Object();

    static {
        // Attempt to load the native library eagerly, but do not throw here so that
        // unit tests can inject a stub via setCffiForTests() before create() is called.
        String libPath = System.getenv("BAML_LIBRARY_PATH");
        try {
            if (libPath != null && !libPath.isEmpty()) {
                cffi = Native.load(libPath, BamlCFFI.class);
            } else {
                cffi = Native.load(System.mapLibraryName("baml_cffi"), BamlCFFI.class);
            }
        } catch (UnsatisfiedLinkError e) {
            cffiLoadError = "Failed to load libbaml_cffi. "
                + "Set BAML_LIBRARY_PATH to the path of libbaml_cffi.so/dylib/dll: "
                + e.getMessage();
        }
    }

    /** Creates a runtime with default options. */
    public static BamlRuntime create(String rootPath, String srcFilesJson, String envVarsJson) {
        return create(rootPath, srcFilesJson, envVarsJson, BamlRuntimeOptions.builder().build());
    }

    /** Creates a runtime with custom options (retry policy, etc.). */
    public static BamlRuntime create(String rootPath, String srcFilesJson, String envVarsJson, BamlRuntimeOptions options) {
        if (cffi == null) {
            throw new RuntimeException(cffiLoadError != null ? cffiLoadError
                : "BAML CFFI library is not loaded. Set BAML_LIBRARY_PATH or call setCffiForTests() first.");
        }
        Pointer ptr = cffi.create_baml_runtime(rootPath, srcFilesJson, envVarsJson);
        if (ptr == null) {
            throw new RuntimeException("Failed to create BAML runtime");
        }
        return new BamlRuntime(ptr, options);
    }

    private BamlRuntime(Pointer ptr, BamlRuntimeOptions options) {
        this.runtimePtr = ptr;
        this.options = options;
        // Register a cleanup action that runs when this instance becomes phantom-reachable.
        // The lambda captures only primitives/references safe to hold after GC, not `this`.
        Pointer capturedPtr = ptr;
        this.cleanable = CLEANER.register(this, () -> {
            if (capturedPtr != null) {
                cffi.destroy_baml_runtime(capturedPtr);
            }
        });
    }

    /**
     * Replace the CFFI implementation for unit tests. Resets callback registration
     * so that callbacks are re-registered against the stub.
     *
     * <p><b>Test-only.</b> Do not call from production code.
     */
    static void setCffiForTests(BamlCFFI stub) {
        cffi = stub;
        callbacksRegistered = false;
        nextCallId.set(1);
        pendingCalls.clear();
        pendingStreams.clear();
    }

    private static void ensureCallbacksRegistered() {
        if (callbacksRegistered) return;
        synchronized (callbackLock) {
            if (callbacksRegistered) return;
            cffi.register_callbacks(RESULT_CALLBACK, ERROR_CALLBACK, ON_TICK_CALLBACK);
            callbacksRegistered = true;
        }
    }

    /**
     * Result callback — invoked by native code for both streaming and non-streaming calls.
     *
     * <ul>
     *   <li>Streaming ({@code pendingStreams}): isDone=0 enqueues a partial event;
     *       isDone=1 completes the final future.</li>
     *   <li>Non-streaming ({@code pendingCalls}): completes the future.</li>
     * </ul>
     */
    private static final ResultCallbackFn RESULT_CALLBACK = (callId, isDone, content, length) -> {
        byte[] copy = (content != null && length > 0)
            ? content.getByteArray(0, (int) length)
            : new byte[0];

        // Streaming path
        StreamState stream = pendingStreams.get(callId);
        if (stream != null) {
            if (isDone != 0) {
                pendingStreams.remove(callId);
                stream.onFinalEvent(copy);
            } else {
                stream.onPartialEvent(copy);
            }
            return;
        }

        // Non-streaming path
        CompletableFuture<byte[]> future = pendingCalls.remove(callId);
        if (future != null) {
            future.complete(copy);
        }
    };

    /**
     * Classify a raw error message string into the appropriate typed exception.
     * Matches on well-known substrings from the Rust CFFI error payloads.
     */
    private static BamlException classifyError(String message) {
        String lower = message.toLowerCase();
        if (lower.contains("rate limit") || lower.contains("too many requests") || lower.contains("429")) {
            return new BamlRateLimitError(message);
        }
        if (lower.contains("timeout") || lower.contains("timed out")) {
            return new BamlTimeoutError(message);
        }
        if (lower.contains("validation") || lower.contains("parse error") || lower.contains("invalid json")) {
            return new BamlValidationError(message);
        }
        if (lower.contains("provider") || lower.contains("api error")) {
            return new BamlProviderError(message, -1);
        }
        return new BamlException(message);
    }

    /** Error callback — invoked by native code when a call fails. */
    private static final ResultCallbackFn ERROR_CALLBACK = (callId, isDone, content, length) -> {
        String message = (content != null && length > 0)
            ? new String(content.getByteArray(0, (int) length), StandardCharsets.UTF_8)
            : "Unknown error";
        BamlException ex = classifyError(message);

        StreamState stream = pendingStreams.remove(callId);
        if (stream != null) {
            stream.onError(ex);
            return;
        }

        CompletableFuture<byte[]> future = pendingCalls.remove(callId);
        if (future != null) {
            future.completeExceptionally(ex);
        }
    };

    private static final OnTickCallbackFn ON_TICK_CALLBACK = (callId) -> {};

    /**
     * Call a BAML function asynchronously. Returns immediately with a
     * {@link CompletableFuture} that completes with the decoded result bytes.
     * Retries (if configured) run off the calling thread.
     */
    public CompletableFuture<byte[]> callFunctionParseAsync(String functionName, byte[] encodedArgs) {
        return CompletableFuture.supplyAsync(() -> callFunctionParse(functionName, encodedArgs), ASYNC_EXECUTOR);
    }

    /**
     * Call a BAML function and block until the final result is available.
     * If a {@link RetryPolicy} is configured, transient errors are retried automatically.
     */
    public byte[] callFunctionParse(String functionName, byte[] encodedArgs) throws BamlException {
        RetryPolicy policy = (options != null) ? options.getRetryPolicy() : null;
        int maxAttempts = (policy != null) ? policy.getMaxAttempts() : 1;
        long baseDelayMs = (policy != null) ? policy.getBaseDelayMs() : 0L;
        double multiplier = (policy != null) ? policy.getMultiplier() : 1.0;
        long maxDelayMs = (policy != null) ? policy.getMaxDelayMs() : 0L;

        BamlException lastException = null;
        long delayMs = baseDelayMs;

        for (int attempt = 1; attempt <= maxAttempts; attempt++) {
            if (attempt > 1 && delayMs > 0) {
                try {
                    Thread.sleep(delayMs);
                } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                    throw new BamlException("Interrupted during retry backoff", ie);
                }
            }

            try {
                return doCallFunctionParse(functionName, encodedArgs);
            } catch (BamlException e) {
                lastException = e;
                if (attempt < maxAttempts) {
                    delayMs = Math.min((long)(delayMs == 0 ? baseDelayMs : delayMs * multiplier), maxDelayMs > 0 ? maxDelayMs : Long.MAX_VALUE);
                }
            }
        }
        throw lastException;
    }

    private byte[] doCallFunctionParse(String functionName, byte[] encodedArgs) throws BamlException {
        ensureCallbacksRegistered();
        int id = nextCallId.getAndIncrement();
        CompletableFuture<byte[]> future = new CompletableFuture<>();
        pendingCalls.put(id, future);

        Buffer buf = cffi.call_function_from_c(runtimePtr, functionName, encodedArgs, encodedArgs.length, id);
        try {
            byte[] responseBytes = (buf.ptr != null && buf.len > 0)
                ? buf.ptr.getByteArray(0, (int) buf.len)
                : new byte[0];
            cffi.free_buffer(buf);

            InvocationResponse response = parseInvocationResponse(responseBytes);
            if (response.getResponseCase() == InvocationResponse.ResponseCase.ERROR) {
                pendingCalls.remove(id);
                throw new BamlException(response.getError());
            }
        } catch (Throwable t) {
            pendingCalls.remove(id);
            if (t instanceof BamlException) throw (BamlException) t;
            throw new BamlException(t.getMessage(), t);
        }

        try {
            return future.get(5, TimeUnit.MINUTES);
        } catch (Exception e) {
            pendingCalls.remove(id);
            throw new BamlException("Call did not complete: " + e.getMessage(), e);
        }
    }

    /**
     * Start a streaming BAML function call. Returns immediately with a {@link BamlStream}
     * whose iterator yields decoded partial results.
     */
    public <PartialT, FinalT> BamlStream<PartialT, FinalT> callFunctionStream(
            String functionName,
            byte[] encodedArgs,
            Function<byte[], PartialT> partialDecoder,
            Function<byte[], FinalT> finalDecoder) throws BamlException {

        ensureCallbacksRegistered();
        int id = nextCallId.getAndIncrement();
        StreamState state = new StreamState();
        pendingStreams.put(id, state);

        Buffer buf = cffi.call_function_stream_from_c(runtimePtr, functionName, encodedArgs, encodedArgs.length, id);
        try {
            byte[] responseBytes = (buf.ptr != null && buf.len > 0)
                ? buf.ptr.getByteArray(0, (int) buf.len)
                : new byte[0];
            cffi.free_buffer(buf);

            InvocationResponse response = parseInvocationResponse(responseBytes);
            if (response.getResponseCase() == InvocationResponse.ResponseCase.ERROR) {
                pendingStreams.remove(id);
                throw new BamlException(response.getError());
            }
        } catch (Throwable t) {
            pendingStreams.remove(id);
            if (t instanceof BamlException) throw (BamlException) t;
            throw new BamlException(t.getMessage(), t);
        }

        return new BamlStream<>(id, state, partialDecoder, finalDecoder);
    }

    private static InvocationResponse parseInvocationResponse(byte[] bytes) {
        try {
            return InvocationResponse.parseFrom(bytes);
        } catch (Exception e) {
            return InvocationResponse.getDefaultInstance();
        }
    }

    public void destroy() {
        cleanable.clean();
    }

    // -----------------------------------------------------------------------
    // Options and RetryPolicy
    // -----------------------------------------------------------------------

    /**
     * Configuration options for a {@link BamlRuntime} instance.
     *
     * <p>Currently supports an optional {@link RetryPolicy}. Create via {@link #builder()}.
     */
    public static final class BamlRuntimeOptions {
        private final RetryPolicy retryPolicy;

        private BamlRuntimeOptions(Builder b) {
            this.retryPolicy = b.retryPolicy;
        }

        public RetryPolicy getRetryPolicy() {
            return retryPolicy;
        }

        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private RetryPolicy retryPolicy;

            public Builder retryPolicy(RetryPolicy policy) {
                this.retryPolicy = policy;
                return this;
            }

            public BamlRuntimeOptions build() {
                return new BamlRuntimeOptions(this);
            }
        }
    }

    /**
     * Retry policy for transient BAML call failures.
     *
     * <p>Create via the factory methods, e.g. {@link #exponentialBackoff}.
     */
    public static final class RetryPolicy {
        private final int maxAttempts;
        private final long maxDelayMs;
        private final long baseDelayMs;
        private final double multiplier;

        private RetryPolicy(int maxAttempts, long maxDelayMs, long baseDelayMs, double multiplier) {
            this.maxAttempts = maxAttempts;
            this.maxDelayMs = maxDelayMs;
            this.baseDelayMs = baseDelayMs;
            this.multiplier = multiplier;
        }

        /**
         * Exponential back-off retry policy.
         *
         * @param maxAttempts  total number of attempts (first + retries)
         * @param maxDelay     upper bound on the per-attempt delay
         * @param baseDelayMs  initial delay in milliseconds (0 = immediate retry)
         * @param multiplier   delay growth factor applied after each attempt
         */
        public static RetryPolicy exponentialBackoff(
                int maxAttempts,
                Duration maxDelay,
                long baseDelayMs,
                double multiplier) {
            return new RetryPolicy(maxAttempts, maxDelay.toMillis(), baseDelayMs, multiplier);
        }

        public int getMaxAttempts() { return maxAttempts; }
        public long getMaxDelayMs() { return maxDelayMs; }
        public long getBaseDelayMs() { return baseDelayMs; }
        public double getMultiplier() { return multiplier; }
    }

    // -----------------------------------------------------------------------
    // StreamState
    // -----------------------------------------------------------------------

    /**
     * Per-call mutable state for a streaming BAML invocation.
     *
     * <p>The native callback thread enqueues partial results via
     * {@link #onPartialEvent(byte[])} and completes the final future via
     * {@link #onFinalEvent(byte[])} or {@link #onError(Throwable)}.
     */
    static final class StreamState {
        private final BlockingQueue<byte[]> eventQueue = new LinkedBlockingQueue<>();
        private final CompletableFuture<byte[]> finalFuture = new CompletableFuture<>();
        private volatile Throwable error;
        private volatile boolean done = false;

        BlockingQueue<byte[]> getEventQueue() { return eventQueue; }
        CompletableFuture<byte[]> getFinalFuture() { return finalFuture; }
        Throwable getError() { return error; }
        boolean isDone() { return done; }
        boolean hasPendingEvents() { return !eventQueue.isEmpty(); }

        void onPartialEvent(byte[] data) {
            eventQueue.offer(data);
        }

        void onFinalEvent(byte[] data) {
            done = true;
            finalFuture.complete(data);
        }

        void onError(Throwable t) {
            error = t;
            done = true;
            finalFuture.completeExceptionally(t);
        }
    }

    // -----------------------------------------------------------------------
    // JNA interfaces and structures
    // -----------------------------------------------------------------------

    /** C callback: (call_id, is_done, content, length) */
    public interface ResultCallbackFn extends Callback {
        void callback(int callId, int isDone, Pointer content, long length);
    }

    public interface OnTickCallbackFn extends Callback {
        void callback(int callId);
    }

    public interface BamlCFFI extends Library {
        void register_callbacks(ResultCallbackFn resultCb, ResultCallbackFn errorCb, OnTickCallbackFn onTickCb);
        Pointer create_baml_runtime(String rootPath, String srcFilesJson, String envVarsJson);
        void destroy_baml_runtime(Pointer runtime);
        /** Non-streaming: callback fires once with the final result (isDone=1). */
        Buffer call_function_from_c(Pointer runtime, String functionName, byte[] encodedArgs, long length, int id);
        /** Streaming: callback fires N times with partials (isDone=0), then once with final (isDone=1). */
        Buffer call_function_stream_from_c(Pointer runtime, String functionName, byte[] encodedArgs, long length, int id);
        void free_buffer(Buffer buffer);
        Buffer version();
    }

    @Structure.FieldOrder({"ptr", "len"})
    public static class Buffer extends Structure implements Structure.ByValue {
        public Pointer ptr;
        public long len;
    }
}
