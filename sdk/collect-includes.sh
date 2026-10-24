#!/bin/bash
# collect-includes.sh — print the ESP-IDF include dirs needed for a target,
# one per line. Works by configuring a scratch IDF project and reading the
# -I flags out of its compile_commands.json.
#
# Usage: collect-includes.sh [--idf-target esp32c6] [--eim-idf NAME]
#                            [--idf-path DIR] [--activation-script FILE]
#                            [--scratch DIR]
# ESP-IDF defaults to the installation selected with `eim select`.
# Prints include dirs to stdout; progress goes to stderr.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=sdk/eim-env.sh
. "$SCRIPT_DIR/eim-env.sh"

IDF_TARGET="${IDF_TARGET:-esp32c6}"
ENV_IDF_PATH="${IDF_PATH:-}"
IDF_PATH_ARG=""
ACTIVATION_SCRIPT=""
OUT_DIR="${OUT_DIR:-$SCRIPT_DIR/build}"
SCRATCH="$OUT_DIR/scratch-idf"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --idf-target)        IDF_TARGET="$2"; shift 2 ;;
    --idf-path)          IDF_PATH_ARG="$2"; shift 2 ;;
    --eim-idf)           EIM_IDF_NAME="$2"; shift 2 ;;
    --activation-script) ACTIVATION_SCRIPT="$2"; shift 2 ;;
    --scratch)           SCRATCH="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

# Resolve the ESP-IDF installation: explicit path first, EIM otherwise.
if [[ -n "$IDF_PATH_ARG" || -n "$ENV_IDF_PATH" ]]; then
  WANT_IDF="${IDF_PATH_ARG:-$ENV_IDF_PATH}"
  if eim_env_resolve "${EIM_IDF_NAME:-}" 2>/dev/null && [[ "${IDF_PATH:-}" == "$WANT_IDF" ]]; then
    ACTIVATION_SCRIPT="${ACTIVATION_SCRIPT:-${IDF_ACTIVATION_SCRIPT:-}}"
  else
    IDF_PATH="$WANT_IDF"
  fi
else
  eim_env_resolve "${EIM_IDF_NAME:-}" || exit 1
  ACTIVATION_SCRIPT="${ACTIVATION_SCRIPT:-${IDF_ACTIVATION_SCRIPT:-}}"
fi
IDF_PATH="${IDF_PATH_ARG:-${ENV_IDF_PATH:-${IDF_PATH:-}}}"

if [[ -z "$ACTIVATION_SCRIPT" ]]; then
  if [[ -f "$IDF_PATH/export.sh" ]]; then
    ACTIVATION_SCRIPT="$IDF_PATH/export.sh"
  else
    echo "error: no activation script for ESP-IDF at $IDF_PATH" >&2
    echo "       install it with EIM, or pass --activation-script" >&2
    exit 1
  fi
fi

rm -rf "$SCRATCH"
mkdir -p "$SCRATCH/main"

cat > "$SCRATCH/CMakeLists.txt" <<EOF
cmake_minimum_required(VERSION 3.16)
include(\$ENV{IDF_PATH}/tools/cmake/project.cmake)
project(sdk_probe)
EOF

cat > "$SCRATCH/main/CMakeLists.txt" <<'EOF'
idf_component_register(SRCS "main.c"
    REQUIRES esp_wifi nvs_flash esp_event esp_netif lwip log esp_timer
             driver esp_adc esp_system esp_common freertos hal soc)
EOF

cat > "$SCRATCH/main/main.c" <<'EOF'
#include "esp_log.h"
#include "esp_wifi.h"
#include "esp_bt.h"
#include "nvs_flash.h"
void app_main(void) {}
EOF

# Enable Wi-Fi and Bluetooth in the scratch sdkconfig so the vendored
# sdkconfig.h carries the CONFIG_BT_* defaults that esp_bt.h's controller
# config macro expands. Apps can override these with their own build/config.
cat > "$SCRATCH/sdkconfig.defaults" <<'EOF'
CONFIG_BT_ENABLED=y
CONFIG_BT_BLE_ENABLED=y
CONFIG_BT_BLUEDROID_ENABLED=y
CONFIG_BT_BLE_42_FEATURES_SUPPORTED=y
EOF

echo "activating ESP-IDF ${EIM_IDF_NAME:-$IDF_PATH}..." >&2
mkdir -p "$OUT_DIR"
# The EIM activation script only treats itself as sourced when $0 is a shell
# name (or zsh); a script sourcing it would otherwise bail out. Run it in a
# nested bash, where $0 is "bash", and configure the scratch project there.
if ! bash -c '
  set -e
  . "$1" >"$2" 2>&1
  cd "$3"
  idf.py set-target "$4" >"$5" 2>&1
  idf.py reconfigure >"$6" 2>&1
' bash "$ACTIVATION_SCRIPT" "$OUT_DIR/export.log" "$SCRATCH" "$IDF_TARGET" \
     "$OUT_DIR/set-target.log" "$OUT_DIR/reconfigure.log"; then
  echo "error: ESP-IDF activation or scratch project configuration failed" >&2
  echo "       see $OUT_DIR/export.log, $OUT_DIR/set-target.log, $OUT_DIR/reconfigure.log" >&2
  exit 1
fi

CC_JSON="$SCRATCH/build/compile_commands.json"
if [[ ! -f "$CC_JSON" ]]; then
  echo "error: idf.py reconfigure failed; no compile_commands.json" >&2
  exit 1
fi

python3 - "$CC_JSON" "$IDF_PATH" "$IDF_TARGET" <<'PY'
import json, os, sys
data = json.load(open(sys.argv[1]))
idf_path, idf_target = sys.argv[2], sys.argv[3]
entry = next((e for e in data if e["file"].endswith("main.c")), data[0])
cmd = entry.get("command") or " ".join(entry["arguments"])
out, i, seen = [], 0, set()
def add(p):
    if p and p not in seen and os.path.isdir(p):
        seen.add(p); out.append(p)
# The app entry's -I set, plus the include dirs of every component the app
# requires (IDF only propagates a component's include dir where it is used).
components = ["esp_wifi", "nvs_flash", "esp_event", "esp_netif", "lwip",
              "log", "esp_timer", "driver", "esp_adc", "esp_system",
              "esp_common", "freertos", "hal", "soc", "esp_partition",
              "esp_blockdev", "nvs", "spi_flash", "esp_mm", "esp_rom",
              # Peripheral drivers and their HALs (GPIO, RMT, LEDC, I2C, SPI,
              # UART). IDF v6 split these out of the legacy `driver` component.
              "esp_driver_gpio", "esp_driver_rmt", "esp_driver_ledc",
              "esp_driver_i2c", "esp_driver_spi", "esp_driver_uart",
              "esp_hal_gpio", "esp_hal_rmt", "esp_hal_ledc",
              "esp_hal_i2c", "esp_hal_spi", "esp_hal_uart",
              "esp_hal_dma", "esp_hal_clock"]
toks = cmd.split()
while i < len(toks):
    if toks[i] == "-I" and i + 1 < len(toks):
        p, i = toks[i+1], i + 2
    elif toks[i].startswith("-I"):
        p, i = toks[i][2:], i + 1
    else:
        i += 1
        continue
    add(p)
for comp in components:
    base = os.path.join(idf_path, "components", comp, "include")
    add(base)
    add(os.path.join(base, idf_target))

# Vendor every IDF component's standard public header dirs, not just the
# components used by the scratch app. This makes new APIs available without
# regenerating the SDK. Non-standard subcomponent include dirs (the FreeRTOS
# kernel, mbedtls, lwip, wpa_supplicant, ...) are already covered by the
# scratch app's compile_commands above because esp_wifi pulls them in.
components_root = os.path.join(idf_path, "components")
# Host-only/emulation components must not shadow target headers (e.g.
# components/linux/include/sys/cdefs.h is libbsd for Linux host builds).
host_only = {"linux", "windows", "host", "darwin", "test", "test_apps", "examples"}
if os.path.isdir(components_root):
    for comp in sorted(os.listdir(components_root)):
        if comp in host_only:
            continue
        base = os.path.join(components_root, comp)
        if not os.path.isdir(base):
            continue
        add(os.path.join(base, "include"))
        add(os.path.join(base, "include", idf_target))
        # Some components nest target headers one level deeper (BT) or keep
        # them under <component>/<target>/include (split HALs). Only the
        # active target's directory: other chips' dirs contain #include_next
        # shims that would shadow the generic header.
        add(os.path.join(base, "include", idf_target, "include"))
        add(os.path.join(base, idf_target, "include"))

# BT/NimBLE/bluedroid public API dirs are not under a plain include/.
bt_root = os.path.join(components_root, "bt")
for sub in ("host/nimble/nimble/nimble/include",
            "host/nimble/port/include",
            "host/nimble/nimble/port/include",
            "host/nimble/nimble/porting/npl/freertos/include",
            "porting/npl/freertos/include",
            "host/bluedroid/api/include/api",
            "host/bluedroid/api/include",
            "common/api/include/api",
            "common/include"):
    add(os.path.join(bt_root, sub))
print("\n".join(out))
PY
