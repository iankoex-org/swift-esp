import ESPBindings
import ESPCore
import ESPShims

@_cdecl("app_main")
func app_main() {
    do {
        try Nvs.initialize()
    } catch {
        fatalError("NVS initialization failed")
    }

    let logger = Logger(label: "app")
    logger.info("boot")

    while true {
        ESP.delay(milliseconds: 1000)
    }
}
