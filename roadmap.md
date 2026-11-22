# Tether roadmap

## Gap matrix (mobbin pass, 2026-11-22)
Compared against ToothFairy, AirBuddy, AllMyBatteries and Bluetooth Battery Monitor from their App Store sheets. One row per minor version, daily use first.

| Gap | Who has it | Size | Status |
|---|---|---|---|
| Global hotkey to reconnect without Spotlight (Carbon hotkey, no permission) | ToothFairy | S | done 1.2.0 (⌃⌥⌘M) |
| Menu bar item: mouse state at a glance, Reconnect, Quit | ToothFairy, AirBuddy | M | done 1.2.0 |
| Open at login (SMAppService), off by default | ToothFairy, AirBuddy | S | done 1.2.0 (macOS 13+) |
| Pick the device: any paired mouse, trackpad or keyboard, not only names with "mouse" | ToothFairy, Bluetooth Battery Monitor | S | todo |
| A quiet notification when it reconnects after a drop | AllMyBatteries, Bluetooth Battery Monitor | S | todo |
| "Bluetooth is ready" status line | Bluetooth Battery Monitor | S | done (Bluetooth Is Off state) |

Skipped: battery level (macOS keeps a BLE mouse's battery private), widgets, history charts, iCloud sync.

## Then
Run the `apple` skill's checks over every state (connecting, connected, not responding, Bluetooth off) in light and dark. Notarize and attach a signed zip to a GitHub release so people can download instead of building.
