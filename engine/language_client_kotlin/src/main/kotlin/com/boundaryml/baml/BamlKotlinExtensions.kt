package com.boundaryml.baml

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.future.await

/**
 * Kotlin coroutine and Flow extensions for [BamlStream].
 *
 * Usage examples:
 *
 * ```kotlin
 * // Await the final result as a suspend function
 * val result: String = functions.LLMEchoStream("Hello").awaitFinal()
 *
 * // Collect partial results as a Kotlin Flow
 * functions.LLMEchoStream("Hello").asFlow().collect { chunk ->
 *     print(chunk)
 * }
 *
 * // Collect partial results AND get the final value
 * val stream = functions.LLMEchoStream("Hello")
 * stream.asFlow().collect { chunk -> print(chunk) }
 * val final = stream.awaitFinal()
 * ```
 */

/**
 * Suspends until the stream's final result is available and returns it decoded as [FinalT].
 *
 * This wraps [BamlStream.getFinalResultAsync] so the calling coroutine is suspended
 * rather than blocking a thread.
 */
suspend fun <PartialT, FinalT> BamlStream<PartialT, FinalT>.awaitFinal(): FinalT =
    getFinalResultAsync().await()

/**
 * Returns a cold [Flow] that emits each partial result as it arrives from the stream.
 *
 * The flow runs the blocking [BamlStream] iterator on the coroutine's dispatcher.
 * For CPU-bound or UI contexts consider switching to [kotlinx.coroutines.Dispatchers.IO]:
 *
 * ```kotlin
 * stream.asFlow()
 *     .flowOn(Dispatchers.IO)
 *     .collect { partial -> updateUi(partial) }
 * ```
 *
 * The flow completes normally when the stream is exhausted. Any [BamlException] thrown
 * by the iterator is propagated as a flow error.
 */
fun <PartialT, FinalT> BamlStream<PartialT, FinalT>.asFlow(): Flow<PartialT> = flow {
    for (partial in this@asFlow) {
        emit(partial)
    }
}
