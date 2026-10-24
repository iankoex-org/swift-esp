#!/bin/bash
# make-sdk.sh — build a portable Swift SDK bundle for an ESP target.
#
# Works for any ESP-IDF target; the triple, -march and -mabi are derived from
# the IDF build itself. RISC-V chips (esp32c2/c3/c5/c6, esp32h2, esp32p4, ...)
# work with a stock swift.org toolchain. Xtensa chips (esp32, esp32s2, esp32s3)
# need Espressif's forked Swift toolchain and are rejected here until it is
# available.
#
# The bundle is self-contained and machine-independent: every header, library
# and module is a real file inside the bundle, and all metadata uses paths
# relative to the bundle — no absolute paths and no symlinks. Small tool
# wrappers locate the swift.org toolchain on the machine that builds, so one
# tarball works on any macOS or Linux host with a matching Swift release.
#
# Bundle layout:
#   swift-sdk.json     schema 4.0 metadata (SE-0387), relative paths only
#   toolset.json       target flags + relative wrapper paths
#   bin/               wrappers that find the host toolchain and inject -I
#   include/           vendored ESP-IDF headers
#   picolibc/          vendored active C library headers (IDF v6+)
#   sdk-root/          sysroot (newlib base headers)
#   swift-resources/   Embedded stdlib + clang builtins, pruned to the target
#
# Usage:
#   sdk/make-sdk.sh [--target esp32c6] [--eim-idf NAME] [--idf-path DIR]
#                   [--sysroot DIR] [--swiftc PATH] [--out DIR]
#
# ESP-IDF defaults to the installation selected with `eim select`. Use
# --eim-idf to pick another EIM-managed version, or --idf-path for a custom
# checkout (in which case its export.sh is used to activate the environment).
#
# After building the bundle:
#   swift sdk install sdk/build/swift-<version>_<target>-idf<idf>-<rev>.tar.gz
#   swift sdk list   # note the installed id, use it in .sourcekit-lsp/config.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=sdk/eim-env.sh
. "$SCRIPT_DIR/eim-env.sh"

# ---------- defaults ----------
IDF_TARGET="${IDF_TARGET:-esp32c6}"
ENV_IDF_PATH="${IDF_PATH:-}"
ENV_ESP_TOOLS="${ESP_TOOLS:-}"
IDF_PATH_ARG=""
OUT_DIR="$SCRIPT_DIR/build"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)   IDF_TARGET="$2"; shift 2 ;;
    --idf-path) IDF_PATH_ARG="$2"; shift 2 ;;
    --eim-idf)  EIM_IDF_NAME="$2"; shift 2 ;;
    --sysroot)  SYSROOT="$2"; shift 2 ;;
    --swiftc)   SWIFTC="$2"; shift 2 ;;
    --out)      OUT_DIR="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

# ---------- resolve ESP-IDF (EIM by default) ----------
# An explicit --idf-path (or $IDF_PATH) wins. Otherwise use the installation
# selected with `eim select`, or the one named with --eim-idf.
if [[ -n "$IDF_PATH_ARG" || -n "$ENV_IDF_PATH" ]]; then
  WANT_IDF="${IDF_PATH_ARG:-$ENV_IDF_PATH}"
  if eim_env_resolve "${EIM_IDF_NAME:-}" 2>/dev/null && [[ "${IDF_PATH:-}" == "$WANT_IDF" ]]; then
    : # activation script belongs to the requested checkout
  else
    IDF_PATH="$WANT_IDF"
    IDF_ACTIVATION_SCRIPT=""
    IDF_TOOLS_PATH="${ENV_ESP_TOOLS:-${IDF_TOOLS_PATH:-$HOME/.espressif/tools}}"
  fi
else
  eim_env_resolve "${EIM_IDF_NAME:-}" || exit 1
fi
IDF_PATH="${IDF_PATH_ARG:-${ENV_IDF_PATH:-${IDF_PATH:-}}}"
ESP_TOOLS="${ENV_ESP_TOOLS:-${IDF_TOOLS_PATH:-$HOME/.espressif/tools}}"

# ---------- detect sysroot for the target ----------
TC_NAME="riscv32-esp-elf"
if [[ -z "${SYSROOT:-}" ]]; then
  case "$IDF_TARGET" in
    esp32c2|esp32c3|esp32c5|esp32c6|esp32h2|esp32h4|esp32p4|esp32c61)
      TC_NAME="riscv32-esp-elf" ;;
    esp32|esp32s2|esp32s3)
      echo "error: '$IDF_TARGET' is Xtensa — needs Espressif's forked Swift toolchain," >&2
      echo "       which swift-sdk.json toolsets cannot drive yet. Use a RISC-V chip" >&2
      echo "       (esp32c3/c6/h2/p4, ...) or contribute Xtensa support." >&2
      exit 1 ;;
    *) echo "error: unknown IDF target '$IDF_TARGET'" >&2; exit 1 ;;
  esac
  RISCV_TC_ROOT="$(ls -d "$ESP_TOOLS/$TC_NAME"/*/ 2>/dev/null | sort -V | tail -1)"
  if [[ -z "$RISCV_TC_ROOT" ]]; then
    echo "error: no $TC_NAME toolchain under $ESP_TOOLS (install via ESP-IDF tools)" >&2
    exit 1
  fi
  SYSROOT="${RISCV_TC_ROOT%/}/$TC_NAME"
fi

# C library headers live in the target subdir of the GCC sysroot.
if [[ ! -d "$SYSROOT/$TC_NAME/include" ]]; then
  echo "error: bad sysroot: $SYSROOT (expected $SYSROOT/$TC_NAME/include)" >&2
  exit 1
fi
NEWLIB_INC="$SYSROOT/$TC_NAME/include"

# ---------- detect swiftc (swift.org toolchain; Xcode's has no riscv32 backend) ----------
if [[ -z "${SWIFTC:-}" ]] && command -v swiftly >/dev/null 2>&1; then
  SWIFTC="$(swiftly run which swiftc 2>/dev/null || true)"
fi
if [[ -z "${SWIFTC:-}" ]]; then
  SWIFTC="$(ls "$HOME/Library/Developer/toolchains"/*/usr/bin/swiftc \
      "$HOME/Library/Developer/Toolchains"/*/usr/bin/swiftc \
      /Library/Developer/Toolchains/*/usr/bin/swiftc \
      "$HOME/.local/share/swiftly/toolchains"/*/usr/bin/swiftc \
      2>/dev/null | sort | tail -1 || true)"
fi
if [[ -z "${SWIFTC:-}" ]] && [[ "$(uname -s)" == "Linux" ]]; then
  # Linux: prefer the toolchain a setup step installed (e.g. /opt/swift —
  # distro runners ship an older preinstalled swift elsewhere on PATH), then
  # PATH, then swiftly's toolchains dir.
  for cand in /opt/swift/bin/swiftc \
              "$(ls -d ~/.local/share/swiftly/toolchains/*/usr/bin/swiftc 2>/dev/null | sort | tail -1)"; do
    if [[ -n "$cand" && -x "$cand" ]]; then SWIFTC="$cand"; break; fi
  done
  if [[ -z "${SWIFTC:-}" ]]; then SWIFTC="$(command -v swiftc || true)"; fi
fi
if [[ -z "$SWIFTC" || ! -x "$SWIFTC" ]]; then
  echo "error: swiftc not found. Install a swift.org toolchain (Xcode's cannot target riscv32)" >&2
  echo "       or pass --swiftc /path/to/swiftc" >&2
  exit 1
fi
TOOLCHAIN_BIN="$(cd "$(dirname "$SWIFTC")" && pwd)"
echo "swiftc:     $SWIFTC"
echo "toolchain:  $TOOLCHAIN_BIN"
echo "sysroot:    $SYSROOT"
echo "IDF_PATH:   $IDF_PATH"
echo "IDF name:   ${EIM_IDF_NAME:-<custom>}"

# ---------- SDK id ----------
SWIFT_VERSION="$("$SWIFTC" -version 2>&1 | sed -nE 's/.*Swift version ([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/p')"
if [[ "$SWIFT_VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
  SWIFT_VERSION="$SWIFT_VERSION.0"
fi
IDF_VERSION=""
if [[ -f "$IDF_PATH/version.txt" ]]; then
  IDF_VERSION="$(tr -d '[:space:]' < "$IDF_PATH/version.txt" | sed 's/^v//')"
fi
if [[ -z "$IDF_VERSION" && -f "$IDF_PATH/tools/cmake/version.cmake" ]]; then
  # EIM checkouts do not ship version.txt; version.cmake is authoritative.
  IDF_VERSION_MAJOR="$(sed -n 's/^set(IDF_VERSION_MAJOR[[:space:]]*\([0-9]*\)).*/\1/p' "$IDF_PATH/tools/cmake/version.cmake")"
  IDF_VERSION_MINOR="$(sed -n 's/^set(IDF_VERSION_MINOR[[:space:]]*\([0-9]*\)).*/\1/p' "$IDF_PATH/tools/cmake/version.cmake")"
  if [[ -n "$IDF_VERSION_MAJOR" && -n "$IDF_VERSION_MINOR" ]]; then
    IDF_VERSION="$IDF_VERSION_MAJOR.$IDF_VERSION_MINOR"
  fi
fi
if [[ -z "$IDF_VERSION" ]]; then
  IDF_VERSION="$(git -C "$IDF_PATH" describe --tags --always 2>/dev/null | sed 's/^v//' || true)"
fi
SDK_REVISION="0.1.0"
if [[ -z "$SWIFT_VERSION" || -z "$IDF_VERSION" ]]; then
  echo "error: could not determine Swift or ESP-IDF version" >&2
  exit 1
fi
BUNDLE_NAME="swift-${SWIFT_VERSION}_${IDF_TARGET}-idf${IDF_VERSION}-${SDK_REVISION}"
echo "sdk id:     $BUNDLE_NAME"

# ---------- collect ESP-IDF include dirs ----------
COLLECT_ARGS=(--idf-target "$IDF_TARGET" --idf-path "$IDF_PATH" --scratch "$OUT_DIR/scratch-idf")
if [[ -n "${IDF_ACTIVATION_SCRIPT:-}" ]]; then
  COLLECT_ARGS+=(--activation-script "$IDF_ACTIVATION_SCRIPT")
fi
INCLUDES="$("$SCRIPT_DIR/collect-includes.sh" "${COLLECT_ARGS[@]}")"
INCLUDE_COUNT="$(echo -n "$INCLUDES" | grep -c . || true)"
echo "collected $INCLUDE_COUNT include dirs"

# C library headers: ESP-IDF v5 uses newlib (sysroot target subdir), v6
# switched to picolibc (specs file).
CFLAGS_FILE="$OUT_DIR/scratch-idf/build/toolchain/cflags"
CLIB_INC="$NEWLIB_INC"
if [[ -f "$CFLAGS_FILE" ]] && grep -q "picolibc.specs" "$CFLAGS_FILE"; then
  CLIB_INC="$SYSROOT/picolibc/include"
fi
if [[ ! -d "$CLIB_INC" ]]; then
  echo "error: C library include dir not found: $CLIB_INC" >&2
  exit 1
fi
echo "C library include: $CLIB_INC"

# Derive triple/-march/-mabi from the target build itself. IDF v5 puts the
# flags in compile_commands.json; IDF v6 writes them to build/toolchain/cflags
# (and no longer passes -mabi — the GCC multilib default for rv32imac is ilp32).
CC_JSON="$OUT_DIR/scratch-idf/build/compile_commands.json"
CFLAGS_FILE="$OUT_DIR/scratch-idf/build/toolchain/cflags"
read -r TRIPLE MARCH MABI <<FLAGS
$(python3 - "$CC_JSON" "$CFLAGS_FILE" <<'PY'
import json, re, sys
cc_json, cflags_file = sys.argv[1], sys.argv[2]
data = json.load(open(cc_json))
entry = next((e for e in data if e["file"].endswith("main.c")), data[0])
cmd = entry.get("command") or " ".join(entry["arguments"])
cc_base = cmd.split()[0].rsplit("/", 1)[-1]
triple = "riscv32-none-none-eabi" if "riscv32" in cc_base else None
march = re.search(r"-march=(\S+)", cmd)
if not march and cflags_file != "-":
    march = re.search(r"-march=(\S+)", open(cflags_file).read())
march = re.sub(r"_x[^ ]*", "", march.group(1)) if march else None
mabi = re.search(r"-mabi=(\S+)", cmd)
mabi = mabi.group(1) if mabi else ("ilp32" if triple else None)
if not (triple and march and mabi):
    sys.exit("could not derive triple/-march/-mabi")
print(triple, march, mabi)
PY
)
FLAGS
echo "triple: $TRIPLE  march: $MARCH  mabi: $MABI"
if [[ -z "$TRIPLE" || -z "$MARCH" || -z "$MABI" ]]; then
  echo "error: failed to derive triple/-march/-mabi for $IDF_TARGET" >&2
  exit 1
fi

# ---------- assemble bundle ----------
BUNDLE="$OUT_DIR/$BUNDLE_NAME"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/sdk-root/include" "$BUNDLE/include"

# ---- sysroot C library headers -------------------------------------------
# The GCC sysroot keeps the base C headers (float.h and friends). The active
# C library (picolibc on IDF v6) is vendored separately: its headers must stay
# in their own search directory so ESP-IDF's `#include_next` shims can chain
# into them. Both paths are injected by the bundle's compiler wrappers.
cp -RL "$NEWLIB_INC/." "$BUNDLE/sdk-root/include/"
if [[ "$CLIB_INC" != "$NEWLIB_INC" ]]; then
  mkdir -p "$BUNDLE/picolibc/include"
  cp -RL "$CLIB_INC/." "$BUNDLE/picolibc/include"
fi

# Copy a header tree over the destination, overwriting files (source wins).
# Directories are merged. Symlinks are dereferenced so the result is portable.
copy_tree() { # $1 = source dir, $2 = destination dir
  local src="$1" dst="$2" f base
  for f in "$src"/*; do
    [[ -e "$f" ]] || continue
    base="$(basename "$f")"
    if [[ -d "$f" ]]; then
      mkdir -p "$dst/$base"
      copy_tree "$f" "$dst/$base"
    else
      cp -L "$f" "$dst/$base"
    fi
  done
}

# ---- ESP-IDF component headers -------------------------------------------
# Clang does not recurse into subdirectories, so headers must appear either
# directly in the include dir (flat files) or as prefix-matching subdirectories
# for includes spelled "freertos/FreeRTOS.h", "soc/reset_reasons.h", etc.
#
# Component trees can provide the same prefix (e.g. generic soc/include and
# soc/esp32c6/include both have a soc/ subdir); these are merged first-wins,
# mirroring C's first-match search over the original -I order.
i=0
while IFS= read -r dir; do
  [[ -z "$dir" ]] && continue
  i=$((i + 1))
  # 1. headers directly in the component include dir
  for f in "$dir"/*.h; do
    [[ -e "$f" ]] || continue
    base="$(basename "$f")"
    # Keep the C library authoritative for names it provides (clang's builtin
    # wrappers #include_next into the C library, not into a flat copy).
    if [[ -e "$CLIB_INC/$base" || -e "$CLIB_INC/sys/$base" ]]; then
      continue
    fi
    cp -L "$f" "$BUNDLE/include/$base"
  done
  # 2. subdirectories for prefix-style includes
  for s in "$dir"/*/; do
    [[ -d "$s" ]] || continue
    base="$(basename "${s%/}")"
    mkdir -p "$BUNDLE/include/$base"
    copy_tree "${s%/}" "$BUNDLE/include/$base"
  done
done <<< "$INCLUDES"

# Compat: picolibc's sys/config.h includes <float.h>, but picolibc ships no
# float.h (clang's builtin wrapper include_next's into the C library). The
# GCC sysroot has one — expose it so module builds resolve.
GCC_FLOAT_H=""
for cand in "$SYSROOT/lib/gcc/$TC_NAME"/*/include/float.h; do
  [[ -e "$cand" ]] && GCC_FLOAT_H="$cand"
done
if [[ -n "$GCC_FLOAT_H" && ! -e "$BUNDLE/include/float.h" ]]; then
  cp -L "$GCC_FLOAT_H" "$BUNDLE/include/float.h"
fi

if [[ ! -e "$BUNDLE/include/sdkconfig.h" ]]; then
  echo "error: sdkconfig.h was not collected from the scratch IDF build" >&2
  exit 1
fi
echo "IDF include/: $(find "$BUNDLE/include" -type f | wc -l | tr -d ' ') files"

# ---- Bluetooth layout ------------------------------------------------------
# esp_bt.h uses #include "../../../../controller/<target>/esp_bt_cfg.h".
# GCC resolves that relative path against the include search dirs, not the
# header's own flattened location, so preserve the BT tree at the same depth.
# The wrapper adds <bundle>/bt/common/api/include/api, making the relative
# include land on <bundle>/bt/controller/<target>/esp_bt_cfg.h.
BT_ROOT="$IDF_PATH/components/bt"
# Only targets whose esp_bt.h includes esp_bt_cfg.h have this file. Some
# targets (e.g. esp32c3 on IDF v6.1) ship a controller directory without it.
if [[ -f "$BT_ROOT/controller/$IDF_TARGET/esp_bt_cfg.h" ]]; then
  mkdir -p "$BUNDLE/bt/controller/$IDF_TARGET" "$BUNDLE/bt/common/api/include/api"
  cp "$BT_ROOT/controller/$IDF_TARGET/esp_bt_cfg.h" \
     "$BUNDLE/bt/controller/$IDF_TARGET/esp_bt_cfg.h"
  if [[ -d "$BT_ROOT/common/api/include/api" ]]; then
    cp -RL "$BT_ROOT/common/api/include/api/." "$BUNDLE/bt/common/api/include/api/"
  fi
fi

# ---- Swift resources ------------------------------------------------------
# The frontend appends "/embedded" to the resource dir in Embedded mode, so
# swift-resources mirrors <toolchain>/usr/lib/swift: embedded/ + clang/ +
# shims/. Everything is copied (not linked) and pruned to the target triple.
SWIFT_RESOURCES="$TOOLCHAIN_BIN/../lib/swift"
if [[ ! -d "$SWIFT_RESOURCES/embedded" ]]; then
  echo "error: no embedded stdlib at $SWIFT_RESOURCES/embedded — toolchain too old?" >&2
  exit 1
fi

EMBED_SRC="$SWIFT_RESOURCES/embedded"
EMBED_DST="$BUNDLE/swift-resources/embedded"
mkdir -p "$EMBED_DST"

# Top-level support files (modulemaps, C++ shims, ...).
for f in "$EMBED_SRC"/*; do
  [[ -f "$f" ]] || continue
  cp -L "$f" "$EMBED_DST/"
done

# Prebuilt modules: keep only the slice for the target triple (the unstripped
# Swift.swiftmodule for all architectures is 718 MB).
for m in "$EMBED_SRC"/*.swiftmodule; do
  [[ -e "$m" ]] || continue
  base="$(basename "$m")"
  if [[ -d "$m" ]]; then
    mkdir -p "$EMBED_DST/$base"
    for f in "$m/$TRIPLE".*; do
      [[ -e "$f" ]] || continue
      cp -L "$f" "$EMBED_DST/$base/"
    done
  else
    cp -L "$m" "$EMBED_DST/"
  fi
done

# Target-specific static libraries.
if [[ -d "$EMBED_SRC/$TRIPLE" ]]; then
  cp -RL "$EMBED_SRC/$TRIPLE" "$EMBED_DST/$TRIPLE"
fi

for extra in shims module.modulemap; do
  if [[ -e "$SWIFT_RESOURCES/$extra" ]]; then
    cp -RL "$SWIFT_RESOURCES/$extra" "$BUNDLE/swift-resources/$extra"
  fi
done

# clang builtin resources. On macOS the toolchain's lib/swift/clang is a
# symlink to ../clang/<version>; on Linux use lib/clang/<version> directly.
# Mirror include/ and share/, and create a real lib/ for our builtins stub.
CLANG_SRC="$SWIFT_RESOURCES/clang"
if [[ ! -d "$CLANG_SRC/include" ]]; then
  CLANG_VER_DIR="$(ls -d "$TOOLCHAIN_BIN/../lib/clang"/*/ 2>/dev/null | sort -V | tail -1 || true)"
  CLANG_SRC="${CLANG_VER_DIR%/}"
fi
if [[ ! -d "$CLANG_SRC/include" ]]; then
  echo "error: clang builtin headers not found in the toolchain" >&2
  exit 1
fi
mkdir -p "$BUNDLE/swift-resources/clang/lib/$TRIPLE"
cp -RL "$CLANG_SRC/include" "$BUNDLE/swift-resources/clang/include"
if [[ -d "$CLANG_SRC/share" ]]; then
  cp -RL "$CLANG_SRC/share" "$BUNDLE/swift-resources/clang/share"
fi

"$TOOLCHAIN_BIN/llvm-ar" rcs "$BUNDLE/swift-resources/clang/lib/$TRIPLE/libclang_rt.builtins.a"

# ---- metadata -------------------------------------------------------------
# All paths are relative to the bundle, so SwiftPM resolves them wherever the
# bundle is installed.
cat > "$BUNDLE/swift-sdk.json" <<EOF
{
  "schemaVersion": "4.0",
  "targetTriples": {
    "$TRIPLE": {
      "sdkRootPath": "sdk-root",
      "swiftResourcesPath": "swift-resources",
      "swiftStaticResourcesPath": "swift-resources",
      "includeSearchPaths": ["include"],
      "toolsetPaths": ["toolset.json"]
    }
  }
}
EOF

# ---- compiler wrappers ----------------------------------------------------
# The wrapper injects the vendored header dirs (SwiftPM cannot pass them to C
# compiles) and then executes the host toolchain. Toolchain discovery happens
# on the machine that builds, never at bundle-generation time.
mkdir -p "$BUNDLE/bin"
cat > "$BUNDLE/bin/_find-toolchain.sh" <<'EOF'
# Sourced by the ESP Swift SDK wrappers. Sets SWIFT_ESP_TC_BIN to a swift.org
# toolchain's bin directory. Override with SWIFT_ESP_TOOLCHAIN_BIN if needed.
_swift_esp_ok() {
  [ -x "$1/swiftc" ] && [ -d "$1/../lib/swift/embedded" ]
}
_swift_esp_find() {
  if [ -n "${SWIFT_ESP_TOOLCHAIN_BIN:-}" ] && _swift_esp_ok "$SWIFT_ESP_TOOLCHAIN_BIN"; then
    SWIFT_ESP_TC_BIN="$SWIFT_ESP_TOOLCHAIN_BIN"; return 0
  fi
  _candidate="$(command -v swiftc 2>/dev/null || true)"
  if [ -n "$_candidate" ]; then
    _dir="$(CDPATH= cd -- "$(dirname -- "$_candidate")" 2>/dev/null && pwd -P)"
    if _swift_esp_ok "$_dir"; then SWIFT_ESP_TC_BIN="$_dir"; return 0; fi
  fi
  if command -v swiftly >/dev/null 2>&1; then
    _candidate="$(swiftly run which swiftc 2>/dev/null || true)"
    if [ -n "$_candidate" ]; then
      _dir="$(CDPATH= cd -- "$(dirname -- "$_candidate")" 2>/dev/null && pwd -P)"
      if _swift_esp_ok "$_dir"; then SWIFT_ESP_TC_BIN="$_dir"; return 0; fi
    fi
  fi
  for _dir in \
      "$HOME/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin" \
      /Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin \
      "$HOME/Library/Developer/Toolchains"/*/usr/bin \
      /Library/Developer/Toolchains/*/usr/bin \
      /opt/swift/usr/bin \
      "$HOME/.local/share/swiftly/toolchains"/*/usr/bin \
      /usr/local/swift/usr/bin; do
    if _swift_esp_ok "$_dir"; then SWIFT_ESP_TC_BIN="$_dir"; return 0; fi
  done
  echo "error: no swift.org toolchain with Embedded Swift support found." >&2
  echo "       Install one, or set SWIFT_ESP_TOOLCHAIN_BIN=/path/to/xctoolchain/usr/bin" >&2
  return 1
}
_swift_esp_find || exit 1
EOF

cat > "$BUNDLE/bin/swiftc" <<'EOF'
#!/bin/sh
self=$0
case "$self" in */*) ;; *) self=$(command -v "$self" 2>/dev/null || printf '%s' "$self") ;; esac
BIN_DIR=$(CDPATH= cd -- "$(dirname -- "$self")" && pwd -P)
BUNDLE=$(CDPATH= cd -- "$BIN_DIR/.." && pwd -P)
. "$BIN_DIR/_find-toolchain.sh"
# Append bundle include paths: flags provided by the app (its build/config
# sdkconfig.h) must take precedence over the bundle's generic defaults.
set -- "$@" -Xcc -I"$BUNDLE/include"
if [ -d "$BUNDLE/picolibc/include" ]; then
  set -- "$@" -Xcc -I"$BUNDLE/picolibc/include"
fi
if [ -d "$BUNDLE/bt/common/api/include/api" ]; then
  set -- "$@" -Xcc -I"$BUNDLE/bt/common/api/include/api"
fi
exec "$SWIFT_ESP_TC_BIN/swiftc" "$@"
EOF

cat > "$BUNDLE/bin/clang" <<'EOF'
#!/bin/sh
self=$0
case "$self" in */*) ;; *) self=$(command -v "$self" 2>/dev/null || printf '%s' "$self") ;; esac
BIN_DIR=$(CDPATH= cd -- "$(dirname -- "$self")" && pwd -P)
BUNDLE=$(CDPATH= cd -- "$BIN_DIR/.." && pwd -P)
. "$BIN_DIR/_find-toolchain.sh"
set -- "$@" -I"$BUNDLE/include"
if [ -d "$BUNDLE/picolibc/include" ]; then
  set -- "$@" -I"$BUNDLE/picolibc/include"
fi
if [ -d "$BUNDLE/bt/common/api/include/api" ]; then
  set -- "$@" -I"$BUNDLE/bt/common/api/include/api"
fi
exec "$SWIFT_ESP_TC_BIN/clang" "$@"
EOF

cat > "$BUNDLE/bin/clang++" <<'EOF'
#!/bin/sh
self=$0
case "$self" in */*) ;; *) self=$(command -v "$self" 2>/dev/null || printf '%s' "$self") ;; esac
BIN_DIR=$(CDPATH= cd -- "$(dirname -- "$self")" && pwd -P)
BUNDLE=$(CDPATH= cd -- "$BIN_DIR/.." && pwd -P)
. "$BIN_DIR/_find-toolchain.sh"
set -- "$@" -I"$BUNDLE/include"
if [ -d "$BUNDLE/picolibc/include" ]; then
  set -- "$@" -I"$BUNDLE/picolibc/include"
fi
if [ -d "$BUNDLE/bt/common/api/include/api" ]; then
  set -- "$@" -I"$BUNDLE/bt/common/api/include/api"
fi
exec "$SWIFT_ESP_TC_BIN/clang++" "$@"
EOF

chmod +x "$BUNDLE/bin/swiftc" "$BUNDLE/bin/clang" "$BUNDLE/bin/clang++"

# Tool paths are relative to the bundle (rootPath resolves against the
# toolset's directory); the wrappers find the host toolchain at build time.
# Only machine-independent target flags live here.
cat > "$BUNDLE/toolset.json" <<EOF
{
  "schemaVersion": "1.0",
  "rootPath": "bin",
  "swiftCompiler": {
    "path": "swiftc",
    "extraCLIOptions": [
      "-enable-experimental-feature", "Embedded",
      "-wmo",
      "-Xfrontend", "-function-sections",
      "-Xfrontend", "-enable-single-module-llvm-emission",
      "-Xcc", "-fno-pic",
      "-Xcc", "-fno-pie",
      "-Xcc", "-march=$MARCH",
      "-Xcc", "-mabi=$MABI"
    ]
  },
  "cCompiler": {
    "path": "clang",
    "extraCLIOptions": ["-march=$MARCH", "-mabi=$MABI", "-fno-pic", "-fno-pie"]
  },
  "cxxCompiler": {
    "path": "clang++",
    "extraCLIOptions": ["-march=$MARCH", "-mabi=$MABI", "-fno-pic", "-fno-pie"]
  }
}
EOF

# ---- portability check ----------------------------------------------------
LINK_COUNT="$(find "$BUNDLE" -type l | wc -l | tr -d ' ')"
if [[ "$LINK_COUNT" != "0" ]]; then
  echo "error: bundle contains $LINK_COUNT symlink(s); it would not be portable" >&2
  find "$BUNDLE" -type l | head -20 >&2
  exit 1
fi
# The wrappers intentionally list standard toolchain locations (for example
# /Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin), which are
# not machine-specific, so only reject genuinely build-local paths here.
LEAKS="$(grep -rIl -e "$HOME" -e "$IDF_PATH" -e "$SYSROOT" \
  "$BUNDLE" 2>/dev/null || true)"
if [[ -n "$LEAKS" ]]; then
  echo "error: bundle references build-machine paths:" >&2
  echo "$LEAKS" | head -20 >&2
  exit 1
fi

# ---------- package as artifact bundle ----------
ABUNDLE="$OUT_DIR/$BUNDLE_NAME.artifactbundle"
rm -rf "$ABUNDLE"
mkdir -p "$ABUNDLE"
cp -R "$BUNDLE" "$ABUNDLE/$BUNDLE_NAME"

# supportedTriples lists HOST triples (SE-0387). The bundle payload is
# host-independent — target headers, target libs, and target modules — so one
# tarball is advertised for both macOS architectures and both Linux ones. The
# build still requires a matching swift.org toolchain on the host.
SUPPORTED_TRIPLES='["arm64-apple-macosx", "x86_64-apple-macosx", "x86_64-unknown-linux-gnu", "aarch64-unknown-linux-gnu", "x86_64-unknown-linux-musl", "aarch64-unknown-linux-musl"'
HOSTTRIPLE="$("$SWIFTC" -print-target-info | python3 -c "import json,sys; print(json.load(sys.stdin)['target']['triple'])")"
SUPPORTED_TRIPLES="$SUPPORTED_TRIPLES, \"$HOSTTRIPLE\"]"
cat > "$ABUNDLE/info.json" <<EOF
{
  "schemaVersion": "1.0",
  "artifacts": {
    "$BUNDLE_NAME": {
      "version": "0.1.0",
      "type": "swiftSDK",
      "variants": [
        {
          "path": "$BUNDLE_NAME",
          "supportedTriples": $SUPPORTED_TRIPLES
        }
      ]
    }
  }
}
EOF

TARBALL="$OUT_DIR/$BUNDLE_NAME.tar.gz"
rm -f "$TARBALL"
COPYFILE_DISABLE=1 tar -C "$OUT_DIR" -czf "$TARBALL" "$BUNDLE_NAME.artifactbundle"

echo
echo "bundle:        $BUNDLE"
echo "tarball:       $TARBALL"
echo "expected sdk id: $BUNDLE_NAME"
echo
echo "next:"
echo "  swift sdk install $TARBALL"
echo "  swift sdk list    # confirm the id matches .sourcekit-lsp/config.json"
