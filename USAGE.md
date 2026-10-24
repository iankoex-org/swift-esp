# Using swift-esp

Build ESP32 firmware in Embedded Swift against ESP-IDF. This guide assumes a
clean host and uses the prebuilt SDK bundles from GitHub release assets.

Do not run `sdk/esp-sdk bundle` for app development. Install the prebuilt SDK and
add the Git dependency; clone the repository only to copy the project template
or examples.

## 1. Host prerequisites

macOS:

```sh
xcode-select --install
# Install Homebrew from https://brew.sh if needed.
brew install cmake ninja python swiftly
```

Linux (Ubuntu/Debian):

```sh
sudo apt-get update
sudo apt-get install -y git wget flex bison gperf cmake ninja-build ccache \
    python3 python3-pip python3-venv libffi-dev libssl-dev dfu-util libusb-1.0-0
```

Install Swift 6.4.1. On macOS:

```sh
swiftly install 6.4.1
swiftly use 6.4.1
swift --version
```

On Linux, install Swiftly, then Swift 6.4.1:

```sh
curl -O https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz
tar zxf swiftly-$(uname -m).tar.gz
./swiftly init
swiftly install 6.4.1
swiftly use 6.4.1
swift --version
```

Published bundles are built with Swift 6.4.1.

## 2. ESP-IDF v6.1 (EIM)

Install ESP-IDF with the ESP-IDF Installation Manager (EIM).

macOS:

```sh
brew tap espressif/eim
brew install eim
```

Ubuntu/Debian:

```sh
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://dl.espressif.com/dl/eim/eim.gpg -o /etc/apt/keyrings/eim.gpg
sudo chmod 0644 /etc/apt/keyrings/eim.gpg
sudo curl -fsSL https://dl.espressif.com/dl/eim/eim.sources -o /etc/apt/sources.list.d/espressif.sources
sudo apt-get update
sudo apt-get install -y eim-cli
```

Then install the version this guide targets and make it active:

```sh
eim install -i v6.1 -t esp32c6
eim select v6.1
eim list
```

EIM installs ESP-IDF, the RISC-V toolchain, CMake, Ninja and a Python
environment under `~/.espressif`. Activate them per shell:

```sh
eim shell v6.1          # interactive shell with the environment active
eim run 'idf.py build'  # one-off command in that environment (version optional
                        # when it is the selected one)
```

## 3. Install the prebuilt SDK

Download the target bundle from the
[Releases](https://github.com/iankoex-org/swift-esp/releases) page:

```sh
# Tags are plain SwiftPM versions; 0.1.0 is the current release.
curl -LO "https://github.com/iankoex-org/swift-esp/releases/download/0.1.0/swift-6.4.1_esp32c6-idf6.1-0.1.0.tar.gz"
swift sdk install ./swift-6.4.1_esp32c6-idf6.1-0.1.0.tar.gz
swift sdk list
```

Installing directly from a URL requires a checksum:

```sh
swift sdk install <url> --checksum <sha256>
```

The bundle is self-contained. It requires the same Swift release (6.4.1) and
ESP-IDF version (6.1) that produced it. With multiple toolchains installed,
set `SWIFT_ESP_TOOLCHAIN_BIN=/path/to/xctoolchain/usr/bin`.

## 4. Create an app

Copy the template (the clone is only for the template):

```sh
git clone --depth 1 https://github.com/iankoex-org/swift-esp.git
cp -R swift-esp/templates/espidf-project my-app
rm -rf swift-esp
cd my-app
```

The template is a complete ESP-IDF project:

```
my-app/
├── CMakeLists.txt
└── main/
    ├── CMakeLists.txt
    ├── Package.swift
    ├── .sourcekit-lsp/config.json
    └── Sources/App/App.swift
```

The template's `Package.swift` uses the Git dependency. If you already have an
ESP-IDF project, copy `templates/espidf-project/main/CMakeLists.txt` into its
`main` component and add the SwiftPM package.

## 5. Package.swift

```swift
// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "App",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "App", type: .static, targets: ["App"]),
    ],
    dependencies: [
        .package(name: "swift-esp", url: "https://github.com/iankoex-org/swift-esp.git", from: "0.1.0"),
    ],
    targets: [
        .target(name: "App", dependencies: [
            .product(name: "ESPCore", package: "swift-esp"),
            .product(name: "ESPShims", package: "swift-esp"),
            .product(name: "ESPBindings", package: "swift-esp"),
        ]),
    ]
)
```

The template and the example above pin the `0.1.0` release. Use
`branch: "main"` only while tracking unreleased changes. The library must be static;
its name determines the archive (`libApp.a`). Add `ESP*` products for the
peripherals used; see [Modules](#8-modules).

## 6. Entry point

```swift
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
```

`app_main` is called by ESP-IDF. All firmware code must be reachable from it.
Embedded Swift has no Foundation or POSIX; use `ESPCore`, `ESPBindings` and the
C APIs.

## 7. ESP-IDF integration

The template's `main/CMakeLists.txt`:

- derives `SWIFT_SDK_ID` from the selected Swift toolchain and ESP-IDF version, then runs `swift build --package-path main -c release --swift-sdk "${SWIFT_SDK_ID}" --build-system native -Xcc -I"${CMAKE_BINARY_DIR}/config"`;
- strips `.swift_modhash`;
- links `.build/riscv32-none-none-eabi/release/libApp.a`.

Adjust it when needed:

- `SWIFT_ARCHIVE` must match the package product name.
- `REQUIRES` must list the IDF components behind the `ESP*` modules:
  `nvs_flash` for `ESPBindings`, `esp_wifi`/`esp_event`/`esp_netif` for
  `ESPWiFi`, `bt` for `ESPBluetooth`, the `esp_driver_*` component for a
  peripheral.
- Components whose symbols are not pulled automatically need
  `-Wl,--undefined=<symbol>` or a linker group. See `examples/wifi` and
  `examples/bluetooth`.

Passing `build/config` lets the Swift package see the project's `sdkconfig.h`.

## 8. Modules

C targets use `CESP` + component; applications import the `ESP*` wrapper:

| Import | Contents |
|---|---|
| `ESPIDF` | Core runtime, FreeRTOS, GPIO, RMT, I2C, SPI, UART, LEDC, ADC |
| `ESPGPIO`, `ESPRMT`, `ESPI2C`, `ESPSPI`, `ESPUART`, `ESPLEDC`, `ESPADC` | One peripheral each |
| `ESPWiFi` | Wi-Fi and netif |
| `ESPBluetooth` | BT controller, Bluedroid, GAP, GATT |
| `ESPShims` | `ESP.delay`, `ESP.check`, `ESP.createTask` |
| `ESPCxx` | C++ bridge (`extern "C"` wrappers) |
| `ESPCore`, `ESPBindings` | Logging and `EspError`/`EspLog`/`Nvs` |

Add only the products the app uses. `ESPIDF` re-exports the core C surface;
peripheral products keep the module graph small.

## 9. Peripheral example

```swift
import ESPGPIO

let pin = gpio_num_t(8)
guard gpio_set_direction(pin, GPIO_MODE_OUTPUT) == ESP_OK else {
    fatalError("GPIO configuration failed")
}
gpio_set_level(pin, 1)
```

The module header (`Sources/CESPGPIO/include/CESPGPIO.h`) lists the exposed IDF
headers. Code is added to the binary only when referenced.

## 10. Shims

`ESPShims` provides `ESP.delay`, `ESP.check`, `ESP.createTask`, and tick
conversion. The raw C shims remain available through `ESPIDF`.

| API | Replaces |
|---|---|
| `ESP.delay(milliseconds:)` | `vTaskDelay(pdMS_TO_TICKS(ms))` |
| `ESP.delay(microseconds:)` | `esp_rom_delay_us(us)` |
| `ESP.ticks(fromMilliseconds:)`, `ESP.milliseconds(fromTicks:)` | `pdMS_TO_TICKS`, `pdTICKS_TO_MS` |
| `ESP.check(_:)` | `ESP_ERROR_CHECK` |
| `ESP.createTask(name:stackDepth:priority:argument:entry:)` | `xTaskCreate` |

`ESPWiFi` adds `shim_wifi_init_config_default()` for
`WIFI_INIT_CONFIG_DEFAULT()`; `ESPBluetooth` adds
`shim_bt_controller_init_config_default()` for
`BT_CONTROLLER_INIT_CONFIG_DEFAULT()`.

Use `Logger`/`EspLog` for ESP-IDF logging. Add a C shim in
`Sources/CESPShims/include/CESPShims.h` for other macros.

## 11. C++

Swift cannot import C++ declarations. Put C++ code behind an `extern "C"`
header and call it from Swift; `ESPCxx` is an example (`cxx_add(1, 2)`). For
app-specific C++, add a C++ target to the app package next to the Swift target.

## 12. Other targets

Download and install the bundle for the target:

```sh
curl -LO "https://github.com/iankoex-org/swift-esp/releases/download/0.1.0/swift-6.4.1_esp32c3-idf6.1-0.1.0.tar.gz"
swift sdk install ./swift-6.4.1_esp32c3-idf6.1-0.1.0.tar.gz
```

Set `.sourcekit-lsp/config.json` to `swift-6.4.1_esp32c3-idf6.1-0.1.0`, then run
`eim run 'idf.py set-target esp32c3' v6.1` (or the same command inside
`eim shell v6.1`). The CMake integration derives the SDK ID from the selected
Swift toolchain and ESP-IDF version.

## 13. Build, flash, monitor

```sh
eim shell v6.1
cd my-app
idf.py set-target esp32c6
idf.py build flash monitor
```

Without an interactive shell, run each step through EIM:

```sh
eim run 'idf.py set-target esp32c6' v6.1
eim run 'idf.py build flash monitor' v6.1
```

`Ctrl+]` exits the monitor. A standalone
`swift build -c release --swift-sdk swift-6.4.1_esp32c6-idf6.1-0.1.0 --build-system native`
only builds the static library.

## 14. Editors

`.sourcekit-lsp/config.json` selects the installed SDK ID. This template uses
`swift-6.4.1_esp32c6-idf6.1-0.1.0`; change it for another target. SourceKit-LSP clients
(VS Code, Neovim) type-check, index and hover against that target.

Xcode can open the package for editing and navigation only. It builds for My
Mac, does not consume the Swift SDK bundle, and cannot debug riscv targets.

## 15. Debugging

OpenOCD over the C6's built-in USB-Serial-JTAG, then LLDB:

```sh
eim run 'openocd -f board/esp32c6-builtin.cfg' v6.1
lldb build/<target>.elf
(lldb) gdb-remote localhost:3333
```

OpenOCD and its scripts come from the EIM tools directory (`$OPENOCD_SCRIPTS`).

## 16. Footprint

Headers and declarations cost zero bytes; only referenced code is linked.

Device: ESP32-C6, chip revision v0.2, 16 MB flash, 512 KB SRAM, 1 MB app
partition. `DIRAM` is the linker's 452 KB (442 KiB) DRAM/IRAM window; `IRAM` is
`.text` in that window, `DRAM` is `.data` + `.bss`.

| Image | Device | `.bin` | Flash code | IRAM | DRAM | DIRAM (used / 452 KB) |
|---|---|---:|---:|---:|---:|---:|
| Minimal Swift app | ESP32-C6 | 163 KB | 117 KB | 39 KB | 12 KB | 51 KB (11%) |
| blink | ESP32-C6 | 207 KB | 157 KB | 42 KB | 13 KB | 55 KB (12%) |
| Wi-Fi scanner | ESP32-C6 | 939 KB | 823 KB | 100 KB | 39 KB | 139 KB (31%) |
| BLE advertiser | ESP32-C6 | 940 KB | 853 KB | 76 KB | 28 KB | 103 KB (23%) |

Exact `.bin` sizes: 163,568 / 207,360 / 939,488 / 940,400 bytes. Blink uses
~20% of the partition; Wi-Fi and BLE leave ~10% headroom. Use a larger
partition table for production.

## 17. Limitations

- `--build-system native` is required for ELF static libraries; SwiftPM marks
  it deprecated.
- RISC-V only. Xtensa targets need a Swift toolchain with an Xtensa backend.
- Function-like macros and variadic functions need shims. C++ needs an
  `extern "C"` bridge. Some mbedtls port-internal headers are not available.
- `EmbeddedPlatformPOSIX` is unavailable on bare-metal.
- The prebuilt Swift modules are compiler-version locked. A 6.4.x bundle is
  rejected by Swift 6.3; build a bundle with the matching Swift release.

Expected build warning: SwiftPM deprecates `--build-system native`, which is
required for ELF static libraries. Regenerate a stale `sdkconfig` if ESP-IDF
reports component-validation warnings.

## 18. Updating the SDK

Install a newer bundle by removing the old one first:

```sh
swift sdk remove swift-6.4.1_esp32c6-idf6.1-0.1.0
swift sdk install ./swift-6.4.1_esp32c6-idf6.1-0.1.0.tar.gz
eim run 'idf.py reconfigure' v6.1
```

`eim run 'idf.py reconfigure' v6.1` recomputes the SDK ID in the CMake integration.

If you switch Swift toolchains (for example after `swiftly use 6.4.1`), run
`idf.py fullclean` before rebuilding. CMake caches the resolved Swift toolchain
and `SWIFT_SDK_ID` in `build/`, so a stale cache fails with "No Swift SDK found
matching query" even though the right bundle is installed.
