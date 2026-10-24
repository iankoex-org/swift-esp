import Foundation

/// Byte-level templates for the SDK bundle and the header probe.
public enum Templates {
    public static let findToolchain = """
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
          for _dir in \\
              "$HOME/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin" \\
              /Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin \\
              "$HOME/Library/Developer/Toolchains"/*/usr/bin \\
              /Library/Developer/Toolchains/*/usr/bin \\
              /opt/swift/usr/bin \\
              "$HOME/.local/share/swiftly/toolchains"/*/usr/bin \\
              /usr/local/swift/usr/bin; do
            if _swift_esp_ok "$_dir"; then SWIFT_ESP_TC_BIN="$_dir"; return 0; fi
          done
          echo "error: no swift.org toolchain with Embedded Swift support found." >&2
          echo "       Install one, or set SWIFT_ESP_TOOLCHAIN_BIN=/path/to/xctoolchain/usr/bin" >&2
          return 1
        }
        _swift_esp_find || exit 1
        """

    public static let swiftcWrapper = """
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
        """

    public static let clangWrapper = """
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
        """

    public static let clangPlusPlusWrapper = """
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
        """

    public static func swiftSDKJSON(triple: String) -> String {
        """
        {
          "schemaVersion": "4.0",
          "targetTriples": {
            "\(triple)": {
              "sdkRootPath": "sdk-root",
              "swiftResourcesPath": "swift-resources",
              "swiftStaticResourcesPath": "swift-resources",
              "includeSearchPaths": ["include"],
              "toolsetPaths": ["toolset.json"]
            }
          }
        }

        """
    }

    public static func toolsetJSON(flags: TargetFlags) -> String {
        """
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
              "-Xcc", "-march=\(flags.march)",
              "-Xcc", "-mabi=\(flags.mabi)"
            ]
          },
          "cCompiler": {
            "path": "clang",
            "extraCLIOptions": ["-march=\(flags.march)", "-mabi=\(flags.mabi)", "-fno-pic", "-fno-pie"]
          },
          "cxxCompiler": {
            "path": "clang++",
            "extraCLIOptions": ["-march=\(flags.march)", "-mabi=\(flags.mabi)", "-fno-pic", "-fno-pie"]
          }
        }

        """
    }

    public static func artifactInfoJSON(name: String, supportedTriples: [String], version: String) -> String {
        let triples = supportedTriples.map { "\"\($0)\"" }.joined(separator: ", ")
        return """
            {
              "schemaVersion": "1.0",
              "artifacts": {
                "\(name)": {
                  "version": "\(version)",
                  "type": "swiftSDK",
                  "variants": [
                    {
                      "path": "\(name)",
                      "supportedTriples": [\(triples)]
                    }
                  ]
                }
              }
            }

            """
    }

    public static let supportedHostTriples = [
        "arm64-apple-macosx",
        "x86_64-apple-macosx",
        "x86_64-unknown-linux-gnu",
        "aarch64-unknown-linux-gnu",
        "x86_64-unknown-linux-musl",
        "aarch64-unknown-linux-musl",
    ]

    public static func probePackage(repoPath: String) -> String {
        """
        // swift-tools-version: 6.3
        import PackageDescription

        let package = Package(
            name: "HeaderProbe",
            products: [.library(name: "Probe", type: .static, targets: ["Probe"])],
            dependencies: [.package(name: "swift-esp", path: "\(repoPath)")],
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

        """
    }

    public static let probeSource = """
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

        """
}
