#include "BamlCFFI.h"
#include <string.h>

static BamlBuffer zero_buffer = {NULL, 0};

// ---------------------------------------------------------------------------
// version
// ---------------------------------------------------------------------------
typedef BamlBuffer (*version_t)(void);
static version_t version_fn = NULL;
void baml_set_version(void *fn) { version_fn = (version_t)fn; }
BamlBuffer baml_version(void) {
    if (version_fn) return version_fn();
    return zero_buffer;
}

// ---------------------------------------------------------------------------
// create_baml_runtime
// ---------------------------------------------------------------------------
typedef const void *(*create_runtime_t)(const char *, const char *, const char *);
static create_runtime_t create_runtime_fn = NULL;
void baml_set_create_runtime(void *fn) { create_runtime_fn = (create_runtime_t)fn; }
const void *baml_create_runtime(const char *root, const char *src, const char *env) {
    if (create_runtime_fn) return create_runtime_fn(root, src, env);
    return NULL;
}

// ---------------------------------------------------------------------------
// destroy_baml_runtime
// ---------------------------------------------------------------------------
typedef void (*destroy_runtime_t)(const void *);
static destroy_runtime_t destroy_runtime_fn = NULL;
void baml_set_destroy_runtime(void *fn) { destroy_runtime_fn = (destroy_runtime_t)fn; }
void baml_destroy_runtime(const void *runtime) {
    if (destroy_runtime_fn) destroy_runtime_fn(runtime);
}

// ---------------------------------------------------------------------------
// register_callbacks
// ---------------------------------------------------------------------------
typedef void (*register_callbacks_t)(BamlCallbackFn, BamlCallbackFn, BamlOnTickFn);
static register_callbacks_t register_callbacks_fn = NULL;
void baml_set_register_callbacks(void *fn) { register_callbacks_fn = (register_callbacks_t)fn; }
void baml_register_callbacks(BamlCallbackFn cb, BamlCallbackFn err_cb, BamlOnTickFn tick_cb) {
    if (register_callbacks_fn) register_callbacks_fn(cb, err_cb, tick_cb);
}

// ---------------------------------------------------------------------------
// call_function_from_c
// ---------------------------------------------------------------------------
typedef BamlBuffer (*call_function_t)(const void *, const char *, const char *, uintptr_t, uint32_t);
static call_function_t call_function_fn = NULL;
void baml_set_call_function(void *fn) { call_function_fn = (call_function_t)fn; }
BamlBuffer baml_call_function(const void *runtime, const char *name,
                               const char *args, uintptr_t len, uint32_t id) {
    if (call_function_fn) return call_function_fn(runtime, name, args, len, id);
    return zero_buffer;
}

// ---------------------------------------------------------------------------
// call_function_stream_from_c
// ---------------------------------------------------------------------------
static call_function_t call_function_stream_fn = NULL;
void baml_set_call_function_stream(void *fn) { call_function_stream_fn = (call_function_t)fn; }
BamlBuffer baml_call_function_stream(const void *runtime, const char *name,
                                      const char *args, uintptr_t len, uint32_t id) {
    if (call_function_stream_fn) return call_function_stream_fn(runtime, name, args, len, id);
    return zero_buffer;
}

// ---------------------------------------------------------------------------
// free_buffer
// ---------------------------------------------------------------------------
typedef void (*free_buffer_t)(BamlBuffer);
static free_buffer_t free_buffer_fn = NULL;
void baml_set_free_buffer(void *fn) { free_buffer_fn = (free_buffer_t)fn; }
void baml_free_buffer(BamlBuffer buf) {
    if (free_buffer_fn) free_buffer_fn(buf);
}

// ---------------------------------------------------------------------------
// cancel_function_call
// ---------------------------------------------------------------------------
typedef BamlBuffer (*cancel_t)(uint32_t);
static cancel_t cancel_fn = NULL;
void baml_set_cancel_function_call(void *fn) { cancel_fn = (cancel_t)fn; }
BamlBuffer baml_cancel_function_call(uint32_t id) {
    if (cancel_fn) return cancel_fn(id);
    return zero_buffer;
}
