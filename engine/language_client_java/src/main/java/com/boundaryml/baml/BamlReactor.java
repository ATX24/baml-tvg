package com.boundaryml.baml;

import reactor.core.publisher.Flux;
import reactor.core.scheduler.Schedulers;

/**
 * Adapter from {@link BamlStream} to Project Reactor's {@link Flux}.
 *
 * <p>{@link BamlStream} iteration is blocking. {@link #toFlux(BamlStream)} runs that
 * iteration on {@link Schedulers#boundedElastic()} so that subscribers are not
 * blocked; override with {@link Flux#subscribeOn(reactor.core.CorePublisher)} if needed.
 *
 * <p><b>Spring WebFlux example:</b> return SSE from a streaming BAML function:
 * <pre>{@code
 * BamlStream<MyPartial, MyFinal> stream = runtime.callFunctionStream(
 *     "MyStreamingFunc", encoded, partialDecoder, finalDecoder);
 * return ServerResponse.ok()
 *     .contentType(MediaType.TEXT_EVENT_STREAM)
 *     .body(BamlReactor.toFlux(stream).map(Object::toString), String.class);
 * }</pre>
 */
public final class BamlReactor {

    private BamlReactor() {}

    /**
     * Converts a {@link BamlStream} into a {@link Flux} of partial results.
     *
     * <p>The stream's iterator is drained on a bounded elastic scheduler.
     * Completion and errors are propagated to the Flux.
     *
     * @param stream the BAML stream (partial type T, final type F)
     * @return Flux that emits each partial result then completes, or errors
     */
    public static <T, F> Flux<T> toFlux(BamlStream<T, F> stream) {
        return Flux.<T>create(sink -> {
            try {
                for (T t : stream) {
                    if (sink.isCancelled()) {
                        return;
                    }
                    sink.next(t);
                }
                sink.complete();
            } catch (Throwable e) {
                sink.error(e);
            }
        }).subscribeOn(Schedulers.boundedElastic());
    }
}
