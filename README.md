# swift-esp

Swift SDK toolchain and bindings for ESP32 RISC-V firmware.

For development on esp32 devices: see [USAGE.md](USAGE.md). This README covers the SDK itself:
building bundles, the module layout, and the development checks.

## Components

| Path | Purpose |
|---|---|
| `sdk/make-sdk.sh` | Builds the portable Swift SDK bundle |
| `sdk/eim-env.sh` | Resolves the EIM-selected ESP-IDF installation |
| `sdk/collect-includes.sh` | Collects ESP-IDF include directories from a scratch project |
| `sdk/check-headers.sh` | Compiles a probe importing every public module |
| `templates/espidf-project/` | App scaffold used by USAGE.md |
| `Sources/CESP*` | Raw C targets over ESP-IDF headers (`CESPIDF`, `CESPRMT`, `CESPWiFi`, ...) |
| `Sources/CESPShims` | C shims for macros and variadic functions |
| `Sources/ESP*` | Swift modules re-exporting the matching `CESP*` target |
| `Sources/ESPBindings` | Ergonomic wrappers (`EspError`, `EspLog`, `Nvs`) |
| `Sources/ESPCore` | Logging and device-agnostic support |

## Bundle

`sdk/make-sdk.sh` produces `swift-<swift>_<target>-idf<idf>-<rev>.tar.gz` containing:

- ESP-IDF and C-library headers under `include/` and `picolibc/`
- the GCC sysroot under `sdk-root/`
- the Embedded Swift stdlib and clang builtins under `swift-resources/`
- POSIX-shell wrappers in `bin/` that find the host toolchain and inject
  bundle-relative include paths

The bundle contains no symlinks and no absolute build-machine paths.
`make-sdk.sh` fails if either appears. `toolset.json` uses relative paths;
`sdk-root`, headers and resources are copied into the bundle.

Bluetooth keeps its original directory layout because `esp_bt.h` uses a
relative include into `controller/<target>/`; the wrapper adds the matching
search root.

## Build the SDK

Prerequisites:

- swift.org toolchain 6.4.1 (Xcode's toolchain has no riscv32 backend)
- ESP-IDF v6.1 installed with EIM: `eim install -i v6.1 -t esp32c6`, then
  `eim select v6.1`
- Python 3.10+

```sh
sdk/make-sdk.sh --target esp32c6
swift sdk install sdk/build/swift-6.4.1_esp32c6-idf6.1-0.1.0.tar.gz
swift sdk list
```

Other RISC-V targets use the same command with `--target esp32c3`, `esp32h2`,
etc. Xtensa targets are rejected. Use `--swiftc` when multiple toolchains are
installed.

Bundles are target-specific because `-march`, `-mabi`, the IDF headers and the
Embedded stdlib slice differ per chip. The compiler itself is resolved from
the host toolchain at build time.

## Develop

Build the package against an installed bundle:

```sh
swift build -c release --swift-sdk swift-6.4.1_esp32c6-idf6.1-0.1.0 --build-system native
```

Run the header/module probe:

```sh
sdk/check-headers.sh
```

Build the examples against the installed bundle:

```sh
eim shell v6.1
(cd examples/blink && idf.py set-target esp32c6 && idf.py build)
(cd examples/wifi && idf.py set-target esp32c6 && idf.py build)
(cd examples/bluetooth && idf.py set-target esp32c6 && idf.py build)
```

`sdk/make-sdk.sh` and `sdk/collect-includes.sh` use the EIM-selected ESP-IDF by
default; pass `--eim-idf NAME` to use another installed version, or
`--idf-path DIR` for a custom checkout.

The examples use a local path dependency for development. The app template in
`templates/espidf-project` uses the Git URL.

## Module layout

C targets use `C` + `ESP` + component (`CESPIDF`, `CESPGPIO`, `CESPWiFi`).
Swift modules use `ESP` + component (`ESPIDF`, `ESPGPIO`, `ESPWiFi`) and
re-export the C target.

To add a peripheral:

1. Add the IDF headers to the relevant `Sources/CESP*/include/CESP*.h`.
2. Add any missing components to `sdk/collect-includes.sh`.
3. Add a Swift wrapper in `Sources/ESP*/` with `@_exported import CESP*`.
4. Register the target, Swift product and probe import in `Package.swift` and
   `sdk/check-headers.sh`.
5. Rebuild and reinstall the bundle if the header set changed.

Ergonomic wrappers live in `Sources/ESPBindings/` as ordinary source files.
Add or change them there directly; nothing is generated at build time.

## CI and releases

`.github/workflows/build-sdk.yml` builds the `esp32c6` and `esp32c3` bundles on
Blacksmith Ubuntu runners, verifies portability, builds the package, the header
probe and all examples with size budgets, and uploads the tarballs. The
Ubuntu-built `esp32c6` bundle is also installed and tested on a Blacksmith
macOS 27 runner. Pushing a version tag (for example `0.1.0`) publishes the
Ubuntu-built bundles as GitHub release assets. Tags are plain SwiftPM versions
(no `v` or `sdk-v` prefix), so one tag names both the package release and its
SDK bundles.

Install a published bundle locally:

```sh
curl -LO https://github.com/iankoex-org/swift-esp/releases/download/0.1.0/swift-6.4.1_esp32c6-idf6.1-0.1.0.tar.gz
swift sdk install ./swift-6.4.1_esp32c6-idf6.1-0.1.0.tar.gz
```

Remote installs require `--checksum`.

## Known limitations

- `--build-system native` is required for ELF static libraries; SwiftPM marks
  it deprecated.
- RISC-V only. Xtensa targets need a Swift toolchain with an Xtensa backend.
- Function-like macros and variadic functions need shims. C++ needs an
  `extern "C"` bridge. Some mbedtls port-internal headers are unavailable.
- `EmbeddedPlatformPOSIX` is unavailable on bare-metal.
- A bundle is tied to the Swift release (6.4.1) and ESP-IDF version (6.1) that
  produced it.

Expected build warning: SwiftPM deprecates `--build-system native`. Regenerate
a stale example `sdkconfig` if ESP-IDF reports component-validation warnings.

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).
