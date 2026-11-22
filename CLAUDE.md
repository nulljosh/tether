# Tether

Reconnects a paired Bluetooth mouse from the keyboard alone. A Mac app (`/Applications/Tether.app`) plus a landing at `tether.jaybulb.com`. No App Store listing.

## Stack
- `Tether.swift`: the whole app. SwiftUI window, IOBluetooth, no dependencies. `Mouse` owns the connect loop, `ContentView` is the one screen.
- `build.sh`: swiftc + actool (icon) + codesign + install. No Xcode project, no xcodegen.
- `web/`: the landing, static assets on a Cloudflare Worker (`wrangler.toml`, `[assets] directory = "web"`).
- `brand/`, `Tether.icon`, `icon.svg`: made by the `/brand` skill. Accent `#16994a`, gradient top `#34c759`.

## Build and deploy
```bash
./build.sh              # installs /Applications/Tether.app
./build.sh release      # also notarizes (asc) and publishes Tether.zip as GitHub release v<CFBundleShortVersionString>
npx wrangler deploy     # landing
```

## How connecting works
Tether learns pointers by name: each tick it reads the HID registry for connected Bluetooth devices with usage mouse (1/2) or touchpad (0x0D/5) and saves their names in UserDefaults (`pointers`). BLE devices report no class of device to IOBluetooth, so this is the only reliable signal, and names survive a re-pair. Every paired device with a learned name, or "mouse"/"trackpad" in its name, gets `openConnection()` on its own thread, then the app polls `isConnected()` every 0.5 s for 10 s. Connected: it polls every 3 s and reconnects if the mouse drops. Missing: it tries again every 12 s or so.

## Gotchas
- `openConnection()` blocks about 15 s on a dead address. Never call it on the main thread or in sequence. The old AppleScript froze doing exactly that.
- The Incase mouse changes address each time it is re-paired, so stale entries pile up in Bluetooth settings. Tether tries them all. Clean them up with Forget This Device in Settings; `blueutil --unpair` does nothing for BLE.
- Tether cannot pair a new mouse. BLE pairing needs the Settings Nearby Devices row (see the `mouse` skill).
- States: connecting, connected, missing, noMouse (nothing learned or paired yet), bluetoothOff, noAccess (`CBManager.authorization` denied).
- BLE mouse battery is not exposed in ioreg or system_profiler, so the app does not show it.
- The Bluetooth permission is tied to the signature. `build.sh` signs with the Developer ID so the grant survives rebuilds. Ad-hoc signing asks again every build, and a user with no mouse cannot click Allow.

## Writing
Same voice as the rest of `~/Documents/Code`: short plain sentences, no em dashes, no emojis.
