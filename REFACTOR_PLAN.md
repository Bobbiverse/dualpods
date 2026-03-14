# UX Refactor Plan - Persistent DualPods Device

## Current Issues
- Creating/destroying aggregate device on activate/deactivate is clunky
- "Create Multi-Output" button is confusing
- Watchdog is always aggressive, even when user wants normal behavior
- No way to manually disable without app interference

## New Design (Mike's Spec)

### 1. Persistent Aggregate Device
- Create "DualPods" aggregate device on app launch (if doesn't exist)
- Never destroy it - it persists in system even when app quits
- Shows up in System Settings → Sound as a permanent option
- Users can select it manually or via app

### 2. Simple Toggle UI
- Menu bar dropdown shows: **Enable DualPods / Disable DualPods**
- Enable = switch system default output to DualPods device
- Disable = switch back to previous device

### 3. Smart Watchdog
- Only runs when DualPods is **enabled** via toggle
- When enabled: auto-restores if system switches away (AirPods wake, YouTube, etc.)
- When disabled: watchdog stops, user has normal macOS behavior

### 4. Bi-Directional State Sync
- App monitors default output device
- If user manually selects DualPods in system preferences → toggle updates to "Enabled"
- If user manually selects another device → toggle updates to "Disabled", watchdog stops

### 5. Volume Sliders
- Always visible (show detected AirPods devices)
- Grayed out when DualPods is disabled
- Active when DualPods is enabled
- Control individual AirPods volumes

## Implementation Plan

### AudioManager Refactor
```swift
@Published var isEnabled: Bool = false  // Replace isActive
@Published var availableAirPods: [AudioDevice] = []  // Detected AirPods
private var dualPodsDeviceID: AudioObjectID = kAudioObjectUnknown  // Persistent device

func ensureDualPodsDeviceExists() {
    // Check if DualPods aggregate already exists
    // If not, create it from detected AirPods
    // Store deviceID but don't destroy on quit
}

func enable() {
    previousDevice = getCurrentDefaultOutputDevice()
    setDefaultOutputDevice(dualPodsDeviceID)
    isEnabled = true
    startWatchdog()
}

func disable() {
    stopWatchdog()
    setDefaultOutputDevice(previousDevice)
    isEnabled = false
}

func handleDefaultDeviceChanged() {
    let current = getCurrentDefaultOutputDevice()
    if current == dualPodsDeviceID && !isEnabled {
        // User manually selected DualPods - enable watchdog
        isEnabled = true
        startWatchdog()
    } else if current != dualPodsDeviceID && isEnabled {
        // User manually selected another device - disable watchdog
        isEnabled = false
        stopWatchdog()
    }
}

func restoreMultiOutputIfNeeded() {
    guard isEnabled else { return }  // Only restore when enabled
    // Rest same as before
}
```

### ContentView Refactor
```swift
VStack {
    // Header with status
    HStack {
        Text("DualPods")
        Circle().fill(audioManager.isEnabled ? .green : .gray)
        Text(audioManager.isEnabled ? "Enabled" : "Disabled")
    }
    
    // Toggle button
    Button(action: {
        if audioManager.isEnabled {
            audioManager.disable()
        } else {
            audioManager.enable()
        }
    }) {
        Text(audioManager.isEnabled ? "Disable DualPods" : "Enable DualPods")
    }
    
    // Volume sliders (always visible)
    ForEach(audioManager.availableAirPods) { device in
        VStack {
            Text(device.name)
            Slider(value: ..., in: 0...1)
                .disabled(!audioManager.isEnabled)  // Gray out when disabled
        }
    }
}
```

## Migration Strategy
1. Create refactor branch
2. Implement AudioManager changes
3. Implement ContentView changes
4. Test thoroughly
5. Update README/DEVELOPMENT docs
6. Merge to master

## Benefits
- Simpler UX: just enable/disable
- Respects user intent: watchdog only when enabled
- Works with system controls: can enable via macOS settings
- Cleaner state management
- Persistent device reduces CoreAudio churn
