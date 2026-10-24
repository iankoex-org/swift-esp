#!/bin/bash
# check-headers.sh — compile-probe every public Swift module/product exposed by
# swift-esp against an installed SDK bundle. Catches missing transitive headers,
# broken module maps, and importer regressions before they reach an app.
#
# Usage:
#   sdk/check-headers.sh [--sdk-id swift-6.4.1_esp32c6-idf6.1-0.1.0]
#
# Requires: swift.org toolchain on PATH (or SWIFT_ESP_TOOLCHAIN_BIN) and the
# SDK bundle already installed with `swift sdk install`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SDK_ID="${SWIFT_ESP_SDK_ID:-swift-6.4.1_esp32c6-idf6.1-0.1.0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sdk-id) SDK_ID="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/swift-esp-headers.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/Sources/Probe"

cat > "$TMP_DIR/Package.swift" <<EOF
// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "HeaderProbe",
    products: [.library(name: "Probe", type: .static, targets: ["Probe"])],
    dependencies: [.package(name: "swift-esp", path: "$REPO_DIR")],
    targets: [
        .target(name: "Probe", dependencies: [
            .product(name: "ESPIDF", package: "swift-esp"),
            .product(name: "ESPShims", package: "swift-esp"),
            .product(name: "ESPGPIO", package: "swift-esp"),
            .product(name: "ESPRMT", package: "swift-esp"),
            .product(name: "ESPI2C", package: "swift-esp"),
            .product(name: "ESPSPI", package: "swift-esp"),
            .product(name: "ESPUART", package: "swift-esp"),
            .product(name: "ESPLEDC", package: "swift-esp"),
            .product(name: "ESPADC", package: "swift-esp"),
            .product(name: "ESPWiFi", package: "swift-esp"),
            .product(name: "ESPBluetooth", package: "swift-esp"),
            .product(name: "ESPCxx", package: "swift-esp"),
            .product(name: "ESPCore", package: "swift-esp"),
            .product(name: "ESPBindings", package: "swift-esp"),
        ])
    ]
)
EOF

cat > "$TMP_DIR/Sources/Probe/Probe.swift" <<'EOF'
import ESPIDF
import ESPShims
import ESPGPIO
import ESPRMT
import ESPI2C
import ESPSPI
import ESPUART
import ESPLEDC
import ESPADC
import ESPWiFi
import ESPBluetooth
import ESPCxx
import ESPCore
import ESPBindings

func probeTask(_ argument: UnsafeMutableRawPointer?) {}

// Touch one representative declaration from every public module. If a header
// or one of its transitive includes is missing, the module build fails here.
@_cdecl("app_main")
func app_main() {
    let logger = Logger(label: "headers")
    logger.info("header probe")

    let _: esp_err_t = ESP_OK
    let _: gpio_num_t = gpio_num_t(8)
    let _ = rmt_tx_channel_config_t()
    let _ = rmt_bytes_encoder_config_t()
    let _ = i2c_master_bus_config_t()
    let _ = spi_bus_config_t()
    let _ = uart_config_t()
    let _ = ledc_timer_config_t()
    let _ = adc_oneshot_unit_init_cfg_t()
    let _ = shim_wifi_init_config_default()
    let _ = shim_bt_controller_init_config_default()
    let _ = cxx_add(1, 2)
    let _ = shim_snprintf_int(nil, 0, "", 0)  // raw C shim via ESPIDF
    let _ = ESP.ticks(fromMilliseconds: 10)
    ESP.delay(microseconds: 10)
    ESP.check(ESP_OK)
    let _ = ESP.createTask(
        name: "probe", stackDepth: 4096, priority: 5, entry: probeTask
    )
}
EOF

echo "building header probe with SDK '$SDK_ID'..."
swift build \
  --package-path "$TMP_DIR" \
  --configuration release \
  --swift-sdk "$SDK_ID" \
  --build-system native
echo "header probe: OK"
