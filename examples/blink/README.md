# Blink — Embedded Swift on ESP32-C6

Cycles the on-board WS2812 RGB LED on GPIO 8 through red, green, blue and off
every 500 ms, logging each step.

The WS2812 needs a timed 24-bit GRB pulse train, so the demo drives it with the
RMT peripheral through `ESPRMT`. For a plain GPIO LED, replace `RgbLed` with:

```swift
import ESPGPIO
import ESPShims

gpio_set_direction(gpio_num_t(8), GPIO_MODE_OUTPUT)
while true {
    gpio_set_level(gpio_num_t(8), 1)
    ESP.delay(milliseconds: 500)
    gpio_set_level(gpio_num_t(8), 0)
    ESP.delay(milliseconds: 500)
}
```

## Prerequisites

See [`USAGE.md`](../../USAGE.md) for host setup and the prebuilt SDK install.

## Build, flash, monitor

```sh
cd examples/blink
eim shell v6.1
idf.py set-target esp32c6
idf.py build flash monitor
```

Exit the monitor with `Ctrl+]`.

Expected output:

```
I (...) blink: WS2812 ready on GPIO 8
I (...) red
I (...) green
I (...) blue
I (...) off
```

`idf.py` runs `swift build --swift-sdk swift-6.4.1_esp32c6-idf6.1-0.1.0`, strips the
`.swift_modhash` section, and links `libBlink.a` into the ESP-IDF app.

The CMake integration derives the same SDK ID from the selected Swift toolchain
and ESP-IDF version. For another RISC-V target, install that target's bundle,
then run `idf.py set-target`. Change the GPIO number in `Blink.swift` for a
different board.
