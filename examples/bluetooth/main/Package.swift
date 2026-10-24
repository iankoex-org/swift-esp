// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "BleAdv",
    platforms: [.macOS(.v13)],
    products: [.library(name: "BleAdv", type: .static, targets: ["BleAdv"])],
    dependencies: [.package(name: "swift-esp", path: "../../..")],
    targets: [
        .target(
            name: "BleAdv",
            dependencies: [
                .product(name: "ESPBluetooth", package: "swift-esp"),
                .product(name: "ESPShims", package: "swift-esp"),
                .product(name: "ESPBindings", package: "swift-esp"),
                .product(name: "ESPCore", package: "swift-esp"),
            ]
        ),
    ]
)
