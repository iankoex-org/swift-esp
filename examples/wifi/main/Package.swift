// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "WifiScan",
    platforms: [.macOS(.v13)],
    products: [.library(name: "WifiScan", type: .static, targets: ["WifiScan"])],
    dependencies: [.package(name: "swift-esp", path: "../../..")],
    targets: [
        .target(
            name: "WifiScan",
            dependencies: [
                .product(name: "ESPWiFi", package: "swift-esp"),
                .product(name: "ESPShims", package: "swift-esp"),
                .product(name: "ESPBindings", package: "swift-esp"),
                .product(name: "ESPCore", package: "swift-esp"),
            ]
        ),
    ]
)
