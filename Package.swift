// swift-tools-version: 6.3
// Swift bindings and tooling for ESP32 (RISC-V) development.
//
// Naming:
//   C targets     C + ESP + component   (CESPIDF, CESPGPIO, CESPWiFi, ...)
//   Swift modules ESP + component       (ESPIDF, ESPGPIO, ESPWiFi, ...)
// The C targets hold the Clang modules; the Swift wrappers re-export them so
// applications import the intuitive ESP* name.
//
// Build: swift build -c release --swift-sdk swift-6.4.1_esp32c6-idf6.1-0.1.0 --build-system native
// (see sdk/ and README.md for the Swift SDK bundle setup)

import PackageDescription

let package = Package(
    name: "swift-esp",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ESPIDF", targets: ["ESPIDF"]),
        .library(name: "ESPShims", targets: ["ESPShims"]),
        .library(name: "ESPGPIO", targets: ["ESPGPIO"]),
        .library(name: "ESPRMT", targets: ["ESPRMT"]),
        .library(name: "ESPI2C", targets: ["ESPI2C"]),
        .library(name: "ESPSPI", targets: ["ESPSPI"]),
        .library(name: "ESPUART", targets: ["ESPUART"]),
        .library(name: "ESPLEDC", targets: ["ESPLEDC"]),
        .library(name: "ESPADC", targets: ["ESPADC"]),
        .library(name: "ESPWiFi", targets: ["ESPWiFi"]),
        .library(name: "ESPBluetooth", targets: ["ESPBluetooth"]),
        .library(name: "ESPCxx", targets: ["ESPCxx"]),
        .library(name: "ESPCore", targets: ["ESPCore"]),
        .library(name: "ESPBindings", targets: ["ESPBindings"]),
    ],
    targets: [
        // MARK: Swift-facing modules (re-export the C targets)

        .target(name: "ESPIDF", dependencies: ["CESPIDF", "CESPShims"], path: "Sources/ESPIDF"),
        .target(name: "ESPShims", dependencies: ["CESPShims"], path: "Sources/ESPShims"),
        .target(name: "ESPGPIO", dependencies: ["CESPGPIO"], path: "Sources/ESPGPIO"),
        .target(name: "ESPRMT", dependencies: ["CESPRMT"], path: "Sources/ESPRMT"),
        .target(name: "ESPI2C", dependencies: ["CESPI2C"], path: "Sources/ESPI2C"),
        .target(name: "ESPSPI", dependencies: ["CESPSPI"], path: "Sources/ESPSPI"),
        .target(name: "ESPUART", dependencies: ["CESPUART"], path: "Sources/ESPUART"),
        .target(name: "ESPLEDC", dependencies: ["CESPLEDC"], path: "Sources/ESPLEDC"),
        .target(name: "ESPADC", dependencies: ["CESPADC"], path: "Sources/ESPADC"),
        .target(name: "ESPWiFi", dependencies: ["CESPWiFi"], path: "Sources/ESPWiFi"),
        .target(name: "ESPBluetooth", dependencies: ["CESPBluetooth"], path: "Sources/ESPBluetooth"),
        .target(name: "ESPCxx", dependencies: ["CESPCxx"], path: "Sources/ESPCxx"),

        // MARK: Raw C targets (Clang modules over ESP-IDF headers)

        .target(name: "CESPIDF", path: "Sources/CESPIDF"),
        .target(name: "CESPShims", path: "Sources/CESPShims"),
        .target(name: "CESPGPIO", path: "Sources/CESPGPIO"),
        .target(name: "CESPRMT", path: "Sources/CESPRMT"),
        .target(name: "CESPI2C", path: "Sources/CESPI2C"),
        .target(name: "CESPSPI", path: "Sources/CESPSPI"),
        .target(name: "CESPUART", path: "Sources/CESPUART"),
        .target(name: "CESPLEDC", path: "Sources/CESPLEDC"),
        .target(name: "CESPADC", path: "Sources/CESPADC"),
        .target(name: "CESPWiFi", path: "Sources/CESPWiFi"),
        .target(name: "CESPBluetooth", path: "Sources/CESPBluetooth"),
        .target(name: "CESPCxx", path: "Sources/CESPCxx"),

        // MARK: Ergonomic wrappers

        .target(
            name: "ESPBindings",
            dependencies: ["CESPIDF", "CESPShims"],
            path: "Sources/ESPBindings"
        ),
        .target(
            name: "ESPCore",
            dependencies: ["CESPShims"],
            path: "Sources/ESPCore"
        ),
    ],
    swiftLanguageModes: [.v6]
)
