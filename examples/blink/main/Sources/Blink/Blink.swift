import ESPRMT
import ESPShims
import ESPCore

/// The RGB LED on the ESP32-C6-DevKitC-1 is a WS2812 addressable LED on
/// GPIO 8. It is not a plain GPIO LED: it expects a 24-bit GRB pulse train,
/// so this demo drives it with the RMT peripheral instead of `gpio_set_level`.
struct RgbLed {
    /// Data-in pin of the on-board WS2812.
    static let gpio: Int32 = 8

    private let channel: rmt_channel_handle_t
    private let encoder: rmt_encoder_handle_t

    init?() {
        var channelConfig = rmt_tx_channel_config_t()
        channelConfig.gpio_num = gpio_num_t(8)
        channelConfig.clk_src = RMT_CLK_SRC_DEFAULT
        channelConfig.resolution_hz = 10_000_000  // 100 ns per RMT tick
        channelConfig.mem_block_symbols = 48
        channelConfig.trans_queue_depth = 4

        var channel: rmt_channel_handle_t?
        guard rmt_new_tx_channel(&channelConfig, &channel) == ESP_OK,
              let channel else { return nil }

        var encoderConfig = rmt_bytes_encoder_config_t()
        // WS2812 timings at 10 MHz: T0H=0.3us, T0L=0.9us; T1H=0.9us, T1L=0.3us.
        // The C structs use bitfields; setting the union's raw value keeps the
        // Swift side simple and matches the hardware layout.
        encoderConfig.bit0.val = 0x0009_8003
        encoderConfig.bit1.val = 0x0003_8009
        encoderConfig.flags.msb_first = 1

        var encoder: rmt_encoder_handle_t?
        guard rmt_new_bytes_encoder(&encoderConfig, &encoder) == ESP_OK,
              let encoder else { return nil }
        guard rmt_enable(channel) == ESP_OK else { return nil }

        self.channel = channel
        self.encoder = encoder
    }

    /// Sends one 24-bit WS2812 frame. The LED latches after the line stays low.
    func set(red: UInt8, green: UInt8, blue: UInt8) {
        // WS2812 expects green, red, blue, most significant bit first.
        // A tuple keeps the three bytes inline (no heap allocation).
        var grb = (green, red, blue)
        var transmitConfig = rmt_transmit_config_t()
        transmitConfig.loop_count = 0

        let result = withUnsafeBytes(of: &grb) { buffer in
            rmt_transmit(channel, encoder, buffer.baseAddress, buffer.count, &transmitConfig)
        }
        if result == ESP_OK {
            _ = rmt_tx_wait_all_done(channel, 1000)
            ESP.delay(microseconds: 100)  // latch time (WS2812 needs >50us low)
        }
    }
}

@_cdecl("app_main")
func app_main() {
    let logger = Logger(label: "blink")
    guard let led = RgbLed() else {
        fatalError("WS2812 init failed on GPIO 8")
    }
    logger.info("blink: WS2812 ready on GPIO \(RgbLed.gpio)")

    var step = 0
    while true {
        switch step % 4 {
        case 0:
            led.set(red: 64, green: 0, blue: 0)
            logger.info("red")
        case 1:
            led.set(red: 0, green: 64, blue: 0)
            logger.info("green")
        case 2:
            led.set(red: 0, green: 0, blue: 64)
            logger.info("blue")
        default:
            led.set(red: 0, green: 0, blue: 0)
            logger.info("off")
        }
        step += 1
        ESP.delay(milliseconds: 500)
    }
}
