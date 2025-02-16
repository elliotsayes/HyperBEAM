#ifndef HB_WASM_WEBGPU_DET_H
#define HB_WASM_WEBGPU_DET_H

#include <wasm_c_api.h>

/**
 * @brief Attempts to register a WebGPU function callback for a given import.
 *
 * This function checks if the provided module and function name match any
 * WebGPU functions that we support. If a match is found, sets the callback
 * pointer to the corresponding WebGPU function implementation.
 *
 * @param module_name The name of the module being imported (e.g. "env")
 * @param name The name of the function being imported (e.g.
 * "wgpuCreateInstance")
 * @param callback_out Pointer to the callback function pointer to be set
 * @return int 1 if a matching WebGPU function was found and callback was set, 0
 * otherwise
 */
int set_callback_webgpu(wasm_byte_t *module_name, wasm_byte_t *name,
                        wasm_func_callback_with_env_t *callback_out);

#endif // HB_WASM_WEBGPU_DET_H
