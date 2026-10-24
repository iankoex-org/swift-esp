# ESP-IDF + SwiftPM app template

1. Install the prebuilt `swift-6.4.1_esp32c6-idf6.1-0.1.0` bundle from the swift-esp GitHub
   releases. Full app setup:
   <https://github.com/iankoex-org/swift-esp/blob/main/USAGE.md>.
2. Build, flash and monitor:

   ```sh
   eim shell v6.1
   idf.py set-target esp32c6
   idf.py build flash monitor
   ```

`main/Package.swift` uses the `swift-esp` Git dependency. When developing the
package locally, replace it with `.package(path: "../../swift-esp")`.

Add IDF components used by the app to `REQUIRES` in `main/CMakeLists.txt`.
