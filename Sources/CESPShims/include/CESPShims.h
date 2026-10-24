// C shims for ESP-IDF macros the ClangImporter cannot import (function-like
// macros with format strings etc.).
//
// ESP_LOG changed API in ESP-IDF v5.5/v6 (ESP_LOG_LEVEL_LOCAL takes an
// esp_log_config_t instead of a bare esp_log_level_t). The shim owns that
// version difference so the Swift side can stay version-agnostic.

#ifndef CESP_SHIMS_H
#define CESP_SHIMS_H

#include "esp_idf_version.h"
#include "esp_log.h"
#include "esp_err.h"
#include "esp_rom_sys.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include <stddef.h>
#include <stdio.h>

static inline void shim_esp_log_level_local(const esp_log_level_t level,
                                            const char *tag,
                                            const char *message) {
// ESP-IDF >= 5.5 has two log macro flavors selected by CONFIG_LOG_VERSION:
//   version 1 (default): ESP_LOG_LEVEL_LOCAL takes a plain esp_log_level_t
//   version 2:           it takes an esp_log_config_t built via
//                        ESP_LOG_CONFIG_INIT(level)
#if ESP_IDF_VERSION >= ESP_IDF_VERSION_VAL(5, 5, 0) && ESP_LOG_VERSION == 2
    ESP_LOG_LEVEL_LOCAL(ESP_LOG_CONFIG_INIT(level), tag, "%s", message);
#else
    ESP_LOG_LEVEL_LOCAL(level, tag, "%s", message);
#endif
}

// FreeRTOS configuration/delay macros and ESP_ERROR_CHECK are function-like
// macros, which the ClangImporter cannot see. These shims give Swift the same
// behaviour with ordinary function calls.
static inline uint32_t shim_ms_to_ticks(uint32_t milliseconds) {
    return (uint32_t)pdMS_TO_TICKS(milliseconds);
}

static inline uint32_t shim_ticks_to_ms(uint32_t ticks) {
    return (uint32_t)pdTICKS_TO_MS(ticks);
}

static inline void shim_delay_ms(uint32_t milliseconds) {
    vTaskDelay(pdMS_TO_TICKS(milliseconds));
}

static inline void shim_esp_error_check(esp_err_t err) {
    ESP_ERROR_CHECK(err);
}

// xTaskCreate is a macro in ESP-IDF's FreeRTOS port (it forwards to
// xTaskCreatePinnedToCore). Expose the plain entry point to Swift.
static inline BaseType_t shim_x_task_create(TaskFunction_t entry,
                                            const char *name,
                                            uint32_t stack_depth,
                                            void *argument,
                                            UBaseType_t priority,
                                            TaskHandle_t *created_task) {
    return xTaskCreate(entry, name, stack_depth, argument, priority, created_task);
}

// Variadic C functions cannot be imported into Swift. These fixed-arity
// wrappers cover the common console/formatting cases with a "%s" message.
static inline void shim_printf(const char *message) {
    printf("%s", message);
}

static inline void shim_esp_rom_printf(const char *message) {
    esp_rom_printf("%s", message);
}

static inline int shim_snprintf_int(char *buffer, size_t size,
                                    const char *label, int value) {
    return snprintf(buffer, size, "%s%d", label, value);
}

#endif /* CESP_SHIMS_H */
