import ESPBindings
import ESPBluetooth
import ESPCore
import ESPShims

/// Starts a BLE peripheral that advertises as "Swift-ESP".
@_cdecl("app_main")
func app_main() {
    let logger = Logger(label: "ble")

    // BT stores RF calibration and host config in NVS.
    do {
        try Nvs.initialize()
    } catch {
        fatalError("NVS initialization failed")
    }

    // BT_CONTROLLER_INIT_CONFIG_DEFAULT() is a macro; the SDK shim returns it.
    var controllerConfig = shim_bt_controller_init_config_default()
    guard esp_bt_controller_init(&controllerConfig) == ESP_OK else {
        fatalError("BT controller init failed")
    }
    guard esp_bt_controller_enable(ESP_BT_MODE_BLE) == ESP_OK else {
        fatalError("BT controller enable failed")
    }
    guard esp_bluedroid_init() == ESP_OK else {
        fatalError("Bluedroid init failed")
    }
    guard esp_bluedroid_enable() == ESP_OK else {
        fatalError("Bluedroid enable failed")
    }

    guard shim_ble_set_default_device_name() == ESP_OK else {
        fatalError("GAP device name failed")
    }

    var advData = esp_ble_adv_data_t()
    advData.set_scan_rsp = false
    advData.include_name = true
    advData.include_txpower = true
    advData.min_interval = 0x20
    advData.max_interval = 0x40
    advData.flag = UInt8(ESP_BLE_ADV_FLAG_GEN_DISC | ESP_BLE_ADV_FLAG_BREDR_NOT_SPT)
    guard esp_ble_gap_config_adv_data(&advData) == ESP_OK else {
        fatalError("GAP advertising data failed")
    }

    // Let the GAP task apply the advertising data before starting.
    ESP.delay(milliseconds: 500)

    var advParams = esp_ble_adv_params_t()
    advParams.adv_int_min = 0x20
    advParams.adv_int_max = 0x40
    advParams.adv_type = ADV_TYPE_IND
    advParams.own_addr_type = BLE_ADDR_TYPE_PUBLIC
    advParams.channel_map = ADV_CHNL_ALL
    advParams.adv_filter_policy = ADV_FILTER_ALLOW_SCAN_ANY_CON_ANY
    guard esp_ble_gap_start_advertising(&advParams) == ESP_OK else {
        fatalError("GAP start advertising failed")
    }

    logger.info("BLE advertising as Swift-ESP")
    while true {
        ESP.delay(milliseconds: 1000)
    }
}
