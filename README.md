# DualPods 🎧

Share AirPods with a friend! Route system audio to multiple Bluetooth devices simultaneously on macOS with independent volume control.

## Features

- **Persistent DualPods device** — appears in System Settings → Sound alongside other devices
- **Simple toggle** — Enable/Disable from menu bar app or system preferences
- **Smart watchdog** — auto-restores DualPods when enabled (YouTube skip, AirPods wake, etc.)
- **Bi-directional sync** — manually select DualPods in macOS and app updates to "Enabled"
- **Per-device volume control** — control each AirPod's volume independently
- **Respects user intent** — watchdog only runs when enabled, stops when you switch to another device
- **Menu bar app** — always accessible, minimal footprint (`LSUIElement`)

## Requirements

- macOS 13.0+
- Xcode 15+
- Two or more Bluetooth audio devices

## Build & Run

1. **Connect 2+ AirPods** to your Mac
2. Open `DualPods.xcodeproj` in Xcode
3. Select your signing team (Signing & Capabilities)
4. Build & Run (⌘R)
5. Click the speaker icon in the menu bar
6. Click **Enable DualPods**

The app creates a persistent "DualPods" device on first launch. You can also enable it by selecting "DualPods" in System Settings → Sound → Output.

## How It Works

DualPods creates a **persistent aggregate device** called "DualPods" using CoreAudio's `AudioHardwareCreateAggregateDevice` API. This device stays in your system (shows up in System Settings → Sound) even when the app quits.

**When enabled:**
- Sets "DualPods" as the default output device
- Starts a watchdog timer that monitors for device changes
- If macOS switches to another device (AirPods wake, YouTube skip, etc.), automatically switches back
- Re-applies your volume settings after every restore

**When disabled:**
- Watchdog stops
- Switches back to your previous device
- You have normal macOS audio behavior

### Architecture

| File | Purpose |
|------|---------|
| `AudioManager.swift` | CoreAudio device management, persistent DualPods creation, enable/disable, watchdog |
| `ContentView.swift` | Menu bar UI with enable/disable toggle and volume sliders |
| `DualPodsApp.swift` | App entry point with NSStatusBar setup |
| `BluetoothMonitor.swift` | IOBluetooth device monitoring (future use) |

### Key APIs Used

- `AudioHardwareCreateAggregateDevice` - creates persistent multi-output device
- `kAudioHardwarePropertyDefaultOutputDevice` - monitors/sets system default device
- `kAudioDevicePropertyVolumeScalar` - per-device volume control
- `kAudioSubDeviceDriftCompensationKey` - clock drift handling for sync
- `AudioObjectPropertyListenerBlock` - bi-directional state sync with system

## Usage

### Enable DualPods (2 ways):
1. **App:** Click menu bar icon → "Enable DualPods"
2. **System:** System Settings → Sound → Output → select "DualPods"

### Disable DualPods (2 ways):
1. **App:** Click menu bar icon → "Disable DualPods"
2. **System:** System Settings → Sound → Output → select any other device

The app and system preferences stay in sync automatically.

### Volume Control

When enabled, use the sliders in the menu bar to control each AirPod's volume independently. When disabled, sliders are grayed out.

## Notes

- **Not sandboxed** — CoreAudio aggregate device creation requires unsandboxed access
- The app runs as an agent (`LSUIElement = true`) so it only appears in the menu bar
- **Connect AirPods first** — app detects AirPods on launch and creates DualPods device
- **Persistent device** — DualPods shows in System Settings → Sound even when app quits
- **Smart watchdog** — only auto-restores when enabled, respects your manual device selection

## Development

See [DEVELOPMENT.md](DEVELOPMENT.md) for architecture details, debugging guide, and UX design decisions.

## License

MIT
