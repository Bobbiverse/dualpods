# DualPods Development Guide

## Project Overview

**DualPods** is a macOS menu bar app that routes audio to multiple Bluetooth devices simultaneously, with independent volume control for each device. Built to solve the problem: "I want to share AirPods with a friend and control our volumes independently."

## Architecture

### Core Components

1. **AudioManager.swift** - CoreAudio interface
   - Device enumeration (`refreshDevices()`)
   - Aggregate device creation (`createAndActivate()`)
   - Per-device volume control (`setVolume()`)
   - Default output device management
   - Property listeners for device list changes

2. **ContentView.swift** - SwiftUI UI
   - Device selection checkboxes (inactive state)
   - Volume sliders for each sub-device (active state)
   - Activate/Deactivate buttons

3. **DualPodsApp.swift** - App entry
   - NSStatusBar setup (menu bar icon)
   - StateObject initialization

4. **BluetoothMonitor.swift** - Bluetooth events
   - Connection/disconnection notifications
   - IOBluetooth device discovery

### How Multi-Output Works

1. User selects 2+ Bluetooth devices from the list
2. App creates an **Aggregate Device** using `AudioHardwareCreateAggregateDevice`
3. App sets the aggregate device as the **default output device**
4. Audio now plays through all selected devices simultaneously
5. App controls volume of each **sub-device** independently

**Key CoreAudio APIs:**
- `AudioHardwareCreateAggregateDevice` - create multi-output device
- `AudioHardwareDestroyAggregateDevice` - cleanup on quit
- `kAudioDevicePropertyVolumeScalar` - per-device volume control
- `kAudioSubDeviceDriftCompensationKey` - sync playback across devices (master=0, secondaries=1)

### State Management

```swift
@Published var outputDevices: [AudioDevice] = []        // Available output devices
@Published var multiOutputDevices: [AudioDevice] = []   // Existing multi-output devices
@Published var activeMultiOutput: AudioDevice?          // Currently active multi-output
@Published var subDevices: [AudioDevice] = []           // Sub-devices with volumes
@Published var isActive: Bool = false                   // Multi-output active?
```

## Known Issues & Bugs

### 🐛 Audio Routing Resets on YouTube Shorts Skip

**Status:** Open (2026-03-14)

**Problem:**
- Multi-output works initially
- User skips to next YouTube Short → audio switches back to single device
- User must manually re-adjust volumes to restore multi-output

**Root Cause:**
- YouTube (or macOS) resets audio routing when loading a new video
- App doesn't detect when the default output device changes
- App shows `isActive = true` but system is no longer using the multi-output device

**Fix Needed:**
Add a property listener for `kAudioHardwarePropertyDefaultOutputDevice` to detect when the system switches away from our aggregate device. Options:

1. **Sticky Mode (Recommended):** Automatically switch back to multi-output device
2. **Update UI:** Set `isActive = false` and notify user

**Implementation:**
```swift
// In AudioManager.init() - add listener for default device changes
private func installDefaultDeviceListener() {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    
    let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.handleDefaultDeviceChanged()
    }
    
    AudioObjectAddPropertyListenerBlock(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        DispatchQueue.main,
        block
    )
}

private func handleDefaultDeviceChanged() {
    guard isActive else { return }
    
    let currentDefault = getCurrentDefaultOutputDevice()
    
    // If we're active but the default device is not our aggregate, switch back
    if aggregateDeviceID != kAudioObjectUnknown && currentDefault != aggregateDeviceID {
        print("⚠️ Default device changed while active - restoring multi-output")
        setDefaultOutputDevice(aggregateDeviceID)
    }
}
```

## Development Workflow

### Building
```bash
cd ~/projects/dualpods
open DualPods.xcodeproj
# Build & Run in Xcode (⌘R)
```

### Testing
1. Connect 2+ Bluetooth devices (AirPods, etc.)
2. Run the app
3. Click menu bar icon
4. Select devices → "Create Multi-Output"
5. Test volume sliders
6. **Test YouTube Shorts skip bug:**
   - Play a YouTube Short
   - Adjust volumes (should work)
   - Skip to next Short
   - **BUG:** Volumes reset, need to re-adjust

### Git Workflow
```bash
git add .
git commit -m "Fix: persistent audio routing on video source changes"
git push origin master
```

## CoreAudio Notes

### Aggregate Device Lifecycle
1. **Create:** `AudioHardwareCreateAggregateDevice(description, &deviceID)`
2. **Set as default:** `AudioObjectSetPropertyData(kAudioHardwarePropertyDefaultOutputDevice)`
3. **Cleanup:** `AudioHardwareDestroyAggregateDevice(deviceID)` on quit

### Volume Control Gotchas
- Volume is **per-sub-device**, not on the aggregate device itself
- Must use `kAudioObjectPropertyScopeOutput`
- Some devices use `mElement = 0` (main), others use `1` and `2` (stereo channels)
- Always check `AudioObjectSetPropertyData` status and retry with different elements

### Drift Compensation
- **Master device:** `kAudioSubDeviceDriftCompensationKey = 0` (no compensation)
- **Secondary devices:** `kAudioSubDeviceDriftCompensationKey = 1` (sync to master)
- Prevents audio desync across multiple Bluetooth devices

## Future Improvements

- [ ] **Fix audio routing persistence** (YouTube skip bug)
- [ ] **Save/Load Presets** - Remember device combinations
- [ ] **Latency Adjustment** - Fine-tune sync between devices
- [ ] **Auto-Activate** - On Bluetooth connection, auto-create multi-output
- [ ] **System-wide hotkey** - Toggle multi-output without clicking menu bar
- [ ] **Visual feedback** - Show which device is currently playing

## Debugging

### Enable Verbose Logging
The app already has extensive `print()` statements. View logs in:
- Xcode Console (when running from Xcode)
- Console.app → filter by "DualPods"

### Common Issues

**"Failed to create multi-output device (error -50)"**
- Error -50 = invalid parameter
- Usually means one of the selected devices is invalid or disconnected
- Run `Refresh` and try again

**"Menu bar icon not showing"**
- Check System Settings → Control Center → "Show in menu bar"
- Fallback: App also creates a regular window (not just menu bar)

**"Volume slider doesn't work"**
- Some devices don't support volume control via CoreAudio
- Try the other device's slider to confirm the app works

## Resources

- [CoreAudio Documentation](https://developer.apple.com/documentation/coreaudio)
- [Audio Hardware Services Reference](https://developer.apple.com/documentation/coreaudio/audio_hardware_services)
- [IOBluetooth Framework](https://developer.apple.com/documentation/iobluetooth)

---

**Last Updated:** 2026-03-14  
**Maintainer:** Bob (Bobbiverse)
