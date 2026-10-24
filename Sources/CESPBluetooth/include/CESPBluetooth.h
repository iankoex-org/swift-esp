// CESPBluetooth — Bluetooth (Bluedroid) bindings for ESP-IDF.
//
// The headers are vendored by sdk/make-sdk.sh. esp_bt.h contains a relative
// include into the BT controller tree; the bundle preserves that layout and
// the compiler wrapper adds the matching search root.

#ifndef CESP_BLUETOOTH_H
#define CESP_BLUETOOTH_H

#include "esp_bt.h"
#include "esp_bt_main.h"
#include "esp_gap_ble_api.h"
#include "esp_gattc_api.h"
#include "esp_gatts_api.h"

// BT_CONTROLLER_INIT_CONFIG_DEFAULT() is a function-like macro the
// ClangImporter cannot expand. Expose it as an ordinary function.
static inline esp_bt_controller_config_t shim_bt_controller_init_config_default(void) {
    esp_bt_controller_config_t config = BT_CONTROLLER_INIT_CONFIG_DEFAULT();
    return config;
}

// Fixed-name helper so the demo does not need Swift-to-C string bridging.
static inline esp_err_t shim_ble_set_default_device_name(void) {
    return esp_ble_gap_set_device_name("Swift-ESP");
}

#endif /* CESP_BLUETOOTH_H */
