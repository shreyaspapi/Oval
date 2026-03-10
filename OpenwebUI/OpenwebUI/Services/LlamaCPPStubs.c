// LlamaCPPStubs.c
// Stub implementations for RunAnywhere LoRA/RAG C symbols that are referenced
// by the RunAnywhere Swift framework but only defined in RunAnywhereLlamaCPP.
// Since we don't use local LLM inference, we provide no-op stubs so the linker
// resolves these symbols without pulling in the full LlamaCPP backend.
//
// All functions return error codes or NULL to indicate "not supported".

#include <stdint.h>
#include <stddef.h>
#include <string.h>

// Use opaque structs passed/returned by value. The linker only cares about
// symbol names and calling convention, not the actual struct layout.

struct rac_rag_config_stub  { int dummy; };
struct rac_rag_query_stub   { int dummy; };
struct rac_rag_result_stub  { int dummy; };

// ---------- LoRA Registry ----------

void* rac_get_lora_registry(void) {
    return NULL;
}

int32_t rac_lora_registry_register(void *registry, const char **tags, int tag_count) {
    return -1;
}

void* rac_lora_registry_get_all(void *registry, int *out_count) {
    if (out_count) *out_count = 0;
    return NULL;
}

void* rac_lora_registry_get_for_model(void *registry, const char *model_id, int *out_count) {
    if (out_count) *out_count = 0;
    return NULL;
}

void rac_lora_entry_array_free(void *array, int count) {
}

// ---------- LLM Component LoRA ----------

int32_t rac_llm_component_load_lora(void *component, const char *path) {
    return -1;
}

int32_t rac_llm_component_remove_lora(void *component, const char *adapter_id) {
    return -1;
}

int32_t rac_llm_component_clear_lora(void *component) {
    return -1;
}

void* rac_llm_component_get_lora_info(void *component, int *out_count) {
    if (out_count) *out_count = 0;
    return NULL;
}

int32_t rac_llm_component_check_lora_compat(void *component, const char *path) {
    return -1;
}

// ---------- RAG Pipeline ----------

int32_t rac_rag_pipeline_create(void *pipeline, struct rac_rag_config_stub config) {
    return -1;
}

void rac_rag_pipeline_destroy(void *pipeline) {
}

int32_t rac_rag_add_document(void *pipeline, const char *text, const char *metadata_json) {
    return -1;
}

int32_t rac_rag_clear_documents(void *pipeline) {
    return -1;
}

int32_t rac_rag_get_document_count(void *pipeline) {
    return 0;
}

struct rac_rag_result_stub rac_rag_query(void *pipeline, struct rac_rag_query_stub query) {
    struct rac_rag_result_stub result;
    memset(&result, 0, sizeof(result));
    return result;
}

void rac_rag_result_free(void *result) {
}

// ---------- RAG Backend Registration ----------

int32_t rac_backend_rag_register(int priority) {
    return -1;
}

void* rac_rag_pipeline_create_standalone(struct rac_rag_config_stub config) {
    return NULL;
}
