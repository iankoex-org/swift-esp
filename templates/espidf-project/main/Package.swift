// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "App",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "App", type: .static, targets: ["App"])
    ],
    dependencies: [
        .package(name: "swift-esp", url: "https://github.com/iankoex-org/swift-esp.git", from: "0.1.0")
    ],
    targets: [
        .target(
            name: "App",
            dependencies: [
                .product(name: "ESPCore", package: "swift-esp"),
                .product(name: "ESPShims", package: "swift-esp"),
                .product(name: "ESPBindings", package: "swift-esp"),
            ]
        )
    ]
)
