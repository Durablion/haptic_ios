# haptic_ios

A minimal SwiftUI iOS app that connects to an ESP32 over BLE and triggers a haptic tap on one of two DRV2605 motors.

## Pairs with

The companion firmware `haptic_ble_tapp.ino` (in [BlindTrack](https://github.com/Durablion/BlindTrack)) running on an ESP32 with two DRV2605 haptic drivers — one on each I²C bus.

## What it does

- Scans for a BLE peripheral named **Haptics-ESP32** advertising service `12345678-1234-1234-1234-123456789abc`.
- Connects automatically.
- **LEFT** button → writes `0x01` → strong click on left DRV2605.
- **RIGHT** button → writes `0x02` → strong click on right DRV2605.

## Requirements

- Xcode 15+
- iOS 16+
- A real iPhone/iPad (BLE doesn't work in the iOS Simulator)
- ESP32 flashed with `haptic_ble_tapp.ino` and two DRV2605 wired to Wire (GPIO 21/22) and Wire1 (GPIO 16/17).

## Build & run

1. Open `haptic_ios.xcodeproj` in Xcode.
2. Select your iOS device and your development team in the target's Signing settings.
3. Build & run. Approve the Bluetooth permission prompt.
