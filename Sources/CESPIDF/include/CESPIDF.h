// Umbrella header for CESPIDF — raw C bindings over ESP-IDF via the ClangImporter.
//
// The headers are vendored into the Swift SDK bundle by sdk/make-sdk.sh (see
// sdk/collect-includes.sh for the component list). Add the headers for the
// IDF components your app uses here; the importer turns them into Swift types
// automatically.
//
// NOTE: keep this list to components whose headers resolve with the include
// set collected from an app entry-point build (sdk/collect-includes.sh).
// Wi-Fi is exposed by CESPWiFi: esp_wifi.h pulls wpa_supplicant internals and
// is kept out of the core umbrella.

#ifndef CESPIDF_H
#define CESPIDF_H

#include "esp_log.h"
#include "nvs_flash.h"
#include "nvs.h"

// Core runtime and FreeRTOS.
#include "esp_err.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "esp_chip_info.h"
#include "esp_heap_caps.h"
#include "esp_rom_sys.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"

// Peripheral drivers. These headers are vendored into the SDK bundle by
// sdk/collect-includes.sh from the esp_driver_*/esp_hal_* components.
#include "driver/gpio.h"
#include "driver/ledc.h"
#include "driver/i2c_master.h"
#include "driver/spi_master.h"
#include "driver/uart.h"
#include "driver/rmt_common.h"
#include "driver/rmt_tx.h"
#include "driver/rmt_encoder.h"
#include "esp_adc/adc_oneshot.h"

#endif /* CESPIDF_H */
