# Wi-Fi scan — Embedded Swift on ESP32-C6

Initializes the station stack and scans for access points every five seconds,
logging SSID, RSSI and primary channel.

## Build, flash, monitor

```sh
cd examples/wifi
eim shell v6.1
idf.py set-target esp32c6
idf.py build flash monitor
```

Expected output:

```
I (...) wifi: scanning every 5s
I (...) wifi: found 7 access points
I (...) wifi: HomeNet  rssi=-47  ch=6
```

Uses `ESPWiFi`, `ESPShims` and `ESPBindings` (NVS). See [`USAGE.md`](../../USAGE.md) for prerequisites.
