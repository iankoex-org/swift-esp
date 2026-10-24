# BLE advertising — Embedded Swift on ESP32-C6

Starts the Bluetooth controller and Bluedroid host, then advertises as
`Swift-ESP`. Scan with a phone (nRF Connect, LightBlue) to see the device.

## Build, flash, monitor

```sh
cd examples/bluetooth
eim shell v6.1
idf.py set-target esp32c6
idf.py build flash monitor
```

Expected output:

```
I (...) ble: BLE advertising as Swift-ESP
```

Uses `ESPBluetooth` and the `BT_CONTROLLER_INIT_CONFIG_DEFAULT()` shim.
`sdkconfig.defaults` enables BT, BLE and the Bluedroid host. See
[`USAGE.md`](../../USAGE.md) for prerequisites.
