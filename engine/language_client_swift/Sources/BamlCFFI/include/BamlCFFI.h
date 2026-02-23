#pragma once

// Mirrors baml_cffi_generated.h exactly.
// This is the Swift equivalent of Go's baml_cffi_wrapper.c:
// - Each Rust symbol gets a Set* function that stores its pointer
// - Each Rust symbol gets a baml_* wrapper that calls through the pointer
//
// C types are used here so Swift can import and use them correctly in
// @convention(c) function types (Swift structs can't be used there).

#include <stdint.h>
#include <stdlib.h>
#include <stdbool.h>

// ---------------------------------------------------------------------------
// Core types (mirror baml_cffi_generated.h)
// ---------------------------------------------------------------------------

typedef struct BamlBuffer {
    const int8_t *ptr;
    size_t len;
} BamlBuffer;

typedef void (*BamlCallbackFn)(uint32_t call_id,
                               int32_t is_done,
                               const int8_t *content,
                               uintptr_t length);

typedef void (*BamlOnTickFn)(uint32_t call_id);

// ---------------------------------------------------------------------------
// version
// ---------------------------------------------------------------------------
void baml_set_version(void *fn);
BamlBuffer baml_version(void);

// ---------------------------------------------------------------------------
// create_baml_runtime / destroy_baml_runtime
// ---------------------------------------------------------------------------
void baml_set_create_runtime(void *fn);
const void *baml_create_runtime(const char *root_path,
                                const char *src_files_json,
                                const char *env_vars_json);

void baml_set_destroy_runtime(void *fn);
void baml_destroy_runtime(const void *runtime);

// ---------------------------------------------------------------------------
// register_callbacks
// ---------------------------------------------------------------------------
void baml_set_register_callbacks(void *fn);
void baml_register_callbacks(BamlCallbackFn callback_fn,
                             BamlCallbackFn error_callback_fn,
                             BamlOnTickFn on_tick_callback_fn);

// ---------------------------------------------------------------------------
// call_function_from_c / call_function_stream_from_c
// ---------------------------------------------------------------------------
void baml_set_call_function(void *fn);
BamlBuffer baml_call_function(const void *runtime,
                              const char *function_name,
                              const char *encoded_args,
                              uintptr_t length,
                              uint32_t id);

void baml_set_call_function_stream(void *fn);
BamlBuffer baml_call_function_stream(const void *runtime,
                                     const char *function_name,
                                     const char *encoded_args,
                                     uintptr_t length,
                                     uint32_t id);

// ---------------------------------------------------------------------------
// free_buffer / cancel_function_call
// ---------------------------------------------------------------------------
void baml_set_free_buffer(void *fn);
void baml_free_buffer(BamlBuffer buf);

void baml_set_cancel_function_call(void *fn);
BamlBuffer baml_cancel_function_call(uint32_t id);
