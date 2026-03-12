# DualPods 🎧

Route system audio to multiple Bluetooth audio devices simultaneously on macOS. Perfect for sharing AirPods with a friend.

## Features

- **Menu bar app** — always accessible, minimal footprint (`LSUIElement`)
- **Auto-detects** connected Bluetooth audio devices (AirPods, Beats, etc.)
- **Programmatic Multi-Output Device** — no Audio MIDI Setup needed
- **Per-device volume control** — the big missing feature from macOS built-in Multi-Output
- **Latency offset** per device to fix sync issues
- **One-click activate/deactivate** — automatically sets system default output
- **Graceful cleanup** — removes the aggregate device on quit

## Requirements

- macOS 13.0+
- Xcode 15+
- Two or more Bluetooth audio devices

## Build & Run

1. Open `DualPods.xcodeproj` in Xcode
2. Select your signing team (Signing & Capabilities)
3. Build & Run (⌘R)
4. Click the AirPods icon in the menu bar
5. Select 2+ devices → click **Activate Multi-Output**

## How It Works

DualPods uses the CoreAudio `AudioHardwareCreateAggregateDevice` API to create a multi-output aggregate device at runtime. This is the same mechanism macOS's Audio MIDI Setup uses, but automated and with per-device volume control.

### Architecture

| File | Purpose |
|------|---------|
| `DualPodsApp.swift` | SwiftUI entry point with `MenuBarExtra` |
| `AudioManager.swift` | CoreAudio device enumeration, aggregate device creation, volume control |
| `BluetoothMonitor.swift` | IOBluetooth device monitoring and connection notifications |
| `ContentView.swift` | Menu bar dropdown UI with device list, volume sliders, latency controls |

### Key APIs Used

- `AudioHardwareCreateAggregateDevice` / `AudioHardwareDestroyAggregateDevice`
- `AudioObjectGetPropertyData` for device enumeration
- `kAudioDevicePropertyVolumeScalar` for per-device volume
- `IOBluetoothDevice` for Bluetooth device detection
- `kAudioSubDeviceDriftCompensationKey` for clock drift handling

## Notes

- **Not sandboxed** — CoreAudio aggregate device creation requires unsandboxed access
- The app runs as an agent (`LSUIElement = true`) so it only appears in the menu bar
- Bluetooth devices must already be connected/paired via System Settings
- Volume control works on the sub-devices directly, not the aggregate device

## License

MIT
