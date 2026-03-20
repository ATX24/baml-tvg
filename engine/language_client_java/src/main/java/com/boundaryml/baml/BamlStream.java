package com.boundaryml.baml;

import java.util.Iterator;
import java.util.NoSuchElementException;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.Function;

/**
 * Streaming wrapper for BAML function calls.
 *
 * <p>Exposes an {@link Iterable} over decoded partial results of type {@code PartialT},
 * plus blocking and non-blocking accessors for the final result of type {@code FinalT}.
 *
 * <ul>
 *   <li>{@link #iterator()} — blocking pull-based iteration over partial results.</li>
 *   <li>{@link #getFinalResult()} — blocks until the stream completes.</li>
 *   <li>{@link #getFinalResultAsync()} — returns a {@link CompletableFuture} that completes
 *       when the stream finishes; the caller's thread is not blocked.</li>
 * </ul>
 *
 * <p>For reactive (Spring WebFlux / Project Reactor) use, wrap with {@code BamlReactor.toFlux()}.
 */
public final class BamlStream<PartialT, FinalT> implements Iterable<PartialT> {

    /** How long the iterator will wait for the next event before re-checking state. */
    private static final long POLL_TIMEOUT_MS = 100;

    private final int callId;
    private final BamlRuntime.StreamState state;
    private final Function<byte[], PartialT> partialDecoder;
    private final Function<byte[], FinalT> finalDecoder;
    private final AtomicBoolean iteratorTaken = new AtomicBoolean(false);

    BamlStream(
        int callId,
        BamlRuntime.StreamState state,
        Function<byte[], PartialT> partialDecoder,
        Function<byte[], FinalT> finalDecoder
    ) {
        this.callId = callId;
        this.state = state;
        this.partialDecoder = partialDecoder;
        this.finalDecoder = finalDecoder;
    }

    public int getCallId() {
        return callId;
    }

    /**
     * Returns an iterator over decoded partial results.
     *
     * <p>The iterator blocks efficiently on the underlying {@link BlockingQueue} —
     * it does not poll with a fixed sleep. Each call to {@link Iterator#hasNext()}
     * waits up to {@value #POLL_TIMEOUT_MS} ms for a new event before checking
     * stream-completion state, then loops.
     */
    @Override
    public Iterator<PartialT> iterator() {
        if (!iteratorTaken.compareAndSet(false, true)) {
            throw new IllegalStateException(
                "BamlStream.iterator() has already been called. " +
                "Each stream may only be iterated once. " +
                "Use getFinalResult() or getFinalResultAsync() to obtain the final value.");
        }
        return new Iterator<PartialT>() {
            private PartialT next;
            private boolean finished = false;

            @Override
            public boolean hasNext() {
                if (finished) return false;
                if (next != null) return true;

                BlockingQueue<byte[]> queue = state.getEventQueue();
                try {
                    while (true) {
                        // Surface any error immediately.
                        Throwable err = state.getError();
                        if (err != null) {
                            finished = true;
                            if (err instanceof RuntimeException) throw (RuntimeException) err;
                            throw new RuntimeException(err);
                        }

                        // Block for up to POLL_TIMEOUT_MS waiting for the next event.
                        byte[] raw = queue.poll(POLL_TIMEOUT_MS, TimeUnit.MILLISECONDS);
                        if (raw != null) {
                            next = partialDecoder.apply(raw);
                            return true;
                        }

                        // No event arrived; if the stream is done and the queue is drained, stop.
                        if (state.isDone() && !state.hasPendingEvents()) {
                            finished = true;
                            return false;
                        }
                        // Otherwise loop — more events may still arrive.
                    }
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    finished = true;
                    return false;
                }
            }

            @Override
            public PartialT next() {
                if (!hasNext()) throw new NoSuchElementException();
                PartialT result = next;
                next = null;
                return result;
            }
        };
    }

    /**
     * Blocks until the final result for this stream is available and returns it decoded as
     * {@code FinalT}.
     *
     * <p>Unlike the old implementation, this method does not poll with a sleep — it blocks
     * on a {@link CompletableFuture} that is completed by the native callback.
     *
     * @throws BamlException if the stream produced an error or the calling thread is interrupted.
     */
    public FinalT getFinalResult() throws BamlException {
        try {
            byte[] raw = state.getFinalFuture().get();
            return finalDecoder.apply(raw);
        } catch (ExecutionException e) {
            Throwable cause = e.getCause();
            if (cause instanceof BamlException) throw (BamlException) cause;
            throw new BamlException(cause != null ? cause.getMessage() : e.getMessage(), cause);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new BamlException("Interrupted while waiting for final stream result", e);
        }
    }

    /**
     * Returns a {@link CompletableFuture} that will be completed with the decoded final result
     * when the stream finishes. The calling thread is never blocked.
     *
     * <p>Errors produced by the stream will surface as {@link java.util.concurrent.CompletionException}
     * wrapping a {@link BamlException} on the returned future.
     */
    public CompletableFuture<FinalT> getFinalResultAsync() {
        return state.getFinalFuture().thenApply(finalDecoder);
    }
}
