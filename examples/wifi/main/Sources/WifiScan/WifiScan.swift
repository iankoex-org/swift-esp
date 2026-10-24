import ESPBindings
import ESPCore
import ESPShims
import ESPWiFi

/// Initializes the Wi-Fi station stack and scans for nearby access points,
/// logging SSID, RSSI and primary channel every five seconds.
@_cdecl("app_main")
func app_main() {
    let logger = Logger(label: "wifi")

    do {
        try Nvs.initialize()
    } catch {
        fatalError("NVS initialization failed")
    }

    guard esp_netif_init() == ESP_OK else { fatalError("esp_netif_init failed") }
    guard esp_event_loop_create_default() == ESP_OK else {
        fatalError("event loop creation failed")
    }
    guard esp_netif_create_default_wifi_sta() != nil else {
        fatalError("wifi station netif creation failed")
    }

    // WIFI_INIT_CONFIG_DEFAULT() is a macro; the SDK shim returns the struct.
    var wifiConfig = shim_wifi_init_config_default()
    guard esp_wifi_init(&wifiConfig) == ESP_OK else { fatalError("esp_wifi_init failed") }
    guard esp_wifi_set_mode(WIFI_MODE_STA) == ESP_OK else { fatalError("STA mode failed") }
    guard esp_wifi_start() == ESP_OK else { fatalError("esp_wifi_start failed") }

    let maxAccessPoints = 10
    let records = UnsafeMutablePointer<wifi_ap_record_t>.allocate(capacity: maxAccessPoints)

    logger.info("wifi: scanning every 5s")

    while true {
        var available = UInt16(maxAccessPoints)
        if esp_wifi_scan_start(nil, true) == ESP_OK {
            var scanned: UInt16 = 0
            if esp_wifi_scan_get_ap_num(&scanned) == ESP_OK {
                available = min(scanned, UInt16(maxAccessPoints))
                if esp_wifi_scan_get_ap_records(&available, records) == ESP_OK {
                    logger.info("found \(available) access points")
                    for index in 0..<Int(available) {
                        let ap = records[index]
                        let ssid = withUnsafeBytes(of: ap.ssid) { raw -> String in
                            let bytes = raw.bindMemory(to: UInt8.self)
                            let end = bytes.firstIndex(of: 0) ?? bytes.count
                            return String(decoding: bytes[0..<end], as: UTF8.self)
                        }
                        logger.info("\(ssid)  rssi=\(ap.rssi)  ch=\(ap.primary)")
                    }
                }
            }
        } else {
            logger.error("scan failed")
        }
        ESP.delay(milliseconds: 5000)
    }
}
