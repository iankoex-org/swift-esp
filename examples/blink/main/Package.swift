// swift-tools-version: 6.3
// Blink — a minimal Embedded Swift app for the ESP32-C6-DevKitC-1.
//
// Build with ESP-IDF, which cross-compiles this package through the swift-esp
// SDK bundle:
//
//   eim shell v6.1
//   idf.py set-target esp32c6
//   idf.py build flash monitor

import PackageDescription

let package = Package(
    name: "Blink",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "Blink", type: .static, targets: ["Blink"])
    ],
    dependencies: [
        // Local checkout while swift-esp is unreleased; switch to a URL
        // dependency once it is published.
        .package(name: "swift-esp", path: "../../..")
    ],
    targets: [
        .target(
            name: "Blink",
            dependencies: [
                // Per-component bindings: RMT + the macro shims + logging.
                .product(name: "ESPRMT", package: "swift-esp"),
                .product(name: "ESPShims", package: "swift-esp"),
                .product(name: "ESPCore", package: "swift-esp"),
            ]
        )
    ]
)
