// swift-tools-version: 6.3
import PackageDescription

// Host-only tooling for swift-esp.
//
// Kept out of the root package on purpose: this builds for the machine running
// the build (Foundation, swift-subprocess), never for riscv32.
let package = Package(
    name: "ESPSDKTooling",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "esp-sdk", targets: ["ESPSDKTool"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-subprocess.git",
            .upToNextMinor(from: "1.0.0")
        )
    ],
    targets: [
        .target(
            name: "ESPSDKCore",
            dependencies: [
                .product(name: "Subprocess", package: "swift-subprocess")
            ],
            path: "Sources/ESPSDKCore"
        ),
        .executableTarget(
            name: "ESPSDKTool",
            dependencies: ["ESPSDKCore"],
            path: "Sources/ESPSDKTool"
        ),
        .testTarget(
            name: "ESPSDKCoreTests",
            dependencies: ["ESPSDKCore"],
            path: "Tests/ESPSDKCoreTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
