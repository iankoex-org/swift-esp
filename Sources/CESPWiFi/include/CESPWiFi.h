// CESPWiFi — per-component bindings for ESP-IDF's WiFi API.
// Import only what you need; the full surface is also in CESPIDF.

#ifndef CESP_WIFI_H
#define CESP_WIFI_H

#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_netif.h"

// WIFI_INIT_CONFIG_DEFAULT() is a function-like macro the ClangImporter cannot
// expand. Expose it as an ordinary function (same pattern as the reference
// ESP32-C6 examples).
static inline wifi_init_config_t shim_wifi_init_config_default(void) {
    wifi_init_config_t config = WIFI_INIT_CONFIG_DEFAULT();
    return config;
}

#endif /* CESP_WIFI_H */
