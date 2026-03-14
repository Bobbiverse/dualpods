import Foundation
import CoreAudio
import AudioToolbox
import Combine

// MARK: - Audio Device Model

struct AudioDevice: Identifiable, Hashable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let isOutput: Bool
    let transportType: UInt32
    var volume: Float = 1.0

    var isBluetooth: Bool {
        transportType == kAudioDeviceTransportTypeBluetooth ||
        transportType == kAudioDeviceTransportTypeBluetoothLE
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AudioDevice, rhs: AudioDevice) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - AudioManager

final class AudioManager: ObservableObject {
    @Published var airpodsDevices: [AudioDevice] = []
    @Published var isEnabled: Bool = false
    @Published var errorMessage: String?

    private var dualPodsDeviceID: AudioObjectID = kAudioObjectUnknown
    private var previousDefaultDevice: AudioObjectID = kAudioObjectUnknown
    private var deviceListListenerBlock: AudioObjectPropertyListenerBlock?
    private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var watchdogTimer: Timer?
    private var isUpdatingState: Bool = false  // Prevent circular updates

    static let aggregateDeviceName = "DualPods Multi-Output"
    static let aggregateDeviceUID = "com.dualpods.multi-output"

    init() {
        print("🔊 AudioManager initializing...")
        refreshDevices()
        ensureDualPodsDeviceExists()
        installDeviceListListener()
        installDefaultDeviceListener()
        syncStateWithSystem()
    }

    deinit {
        stopWatchdog()
        removeDeviceListListener()
        removeDefaultDeviceListener()
        // Don't destroy the aggregate device - it's persistent
    }

    // MARK: - Persistent DualPods Device

    func ensureDualPodsDeviceExists() {
        // Check if DualPods aggregate device already exists
        if let existingDevice = findDualPodsDevice() {
            // Destroy and recreate to ensure it's configured correctly
            print("🗑️ Found existing DualPods device, recreating to ensure correct configuration...")
            AudioHardwareDestroyAggregateDevice(existingDevice.id)
        }

        // Create fresh device
        createDualPodsDevice()
    }

    private func findDualPodsDevice() -> AudioDevice? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )
        guard status == noErr else { return nil }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else { return nil }

        for deviceID in deviceIDs {
            if let uid = getDeviceStringProperty(deviceID, selector: kAudioDevicePropertyDeviceUID),
               uid == Self.aggregateDeviceUID {
                return queryDevice(deviceID)
            }
        }

        return nil
    }

    private func createDualPodsDevice() {
        refreshDevices()
        let connectedAirPods = airpodsDevices
        
        guard connectedAirPods.count >= 2 else {
            errorMessage = "Connect at least 2 AirPods to create DualPods device"
            print("⚠️ Need at least 2 AirPods, found \(connectedAirPods.count)")
            return
        }

        print("🔧 Creating DualPods device with \(connectedAirPods.count) AirPods:")
        for (index, device) in connectedAirPods.enumerated() {
            print("   [\(index)] \(device.name) (UID: \(device.uid))")
        }

        let subDevices: [[String: Any]] = connectedAirPods.enumerated().map { index, device in
            [
                kAudioSubDeviceUIDKey: device.uid,
                kAudioSubDeviceDriftCompensationKey: index == 0 ? 0 : 1
            ] as [String: Any]
        }

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: Self.aggregateDeviceName,
            kAudioAggregateDeviceUIDKey: Self.aggregateDeviceUID,
            kAudioAggregateDeviceSubDeviceListKey: subDevices,
            kAudioAggregateDeviceMasterSubDeviceKey: connectedAirPods[0].uid,
            kAudioAggregateDeviceIsPrivateKey: 0,
            kAudioAggregateDeviceIsStackedKey: 0
        ]

        var newDeviceID: AudioObjectID = kAudioObjectUnknown
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &newDeviceID)

        if status != noErr {
            errorMessage = "Failed to create DualPods device (error \(status))"
            print("❌ Failed to create DualPods: \(status)")
            return
        }

        dualPodsDeviceID = newDeviceID
        print("✅ Created persistent DualPods device: \(newDeviceID)")
        
        // Load volumes for the AirPods
        for i in 0..<airpodsDevices.count {
            airpodsDevices[i].volume = getVolumeForDevice(airpodsDevices[i].id)
        }
    }

    private func loadAirPodsFromDualPodsDevice(_ device: AudioDevice) {
        let subDeviceIDs = getSubDeviceIDs(device.id)
        var devices: [AudioDevice] = []
        
        for subID in subDeviceIDs {
            if var dev = queryDevice(subID), dev.isBluetooth {
                dev.volume = getVolumeForDevice(subID)
                devices.append(dev)
            }
        }
        
        DispatchQueue.main.async {
            self.airpodsDevices = devices
        }
        print("📱 Loaded \(devices.count) AirPods from DualPods device")
    }

    // MARK: - Enable / Disable

    func enable() {
        guard dualPodsDeviceID != kAudioObjectUnknown else {
            errorMessage = "DualPods device not found"
            return
        }

        isUpdatingState = true
        previousDefaultDevice = getCurrentDefaultOutputDevice()
        setDefaultOutputDevice(dualPodsDeviceID)
        
        DispatchQueue.main.async {
            self.isEnabled = true
            self.errorMessage = nil
        }
        
        startWatchdog()
        print("✅ DualPods enabled")
        isUpdatingState = false
    }

    func disable() {
        isUpdatingState = true
        stopWatchdog()

        if previousDefaultDevice != kAudioObjectUnknown {
            setDefaultOutputDevice(previousDefaultDevice)
        }

        DispatchQueue.main.async {
            self.isEnabled = false
        }
        
        print("🔴 DualPods disabled")
        isUpdatingState = false
    }

    // MARK: - Device Enumeration

    func refreshDevices() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )
        guard status == noErr else { return }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else { return }

        var newAirPods: [AudioDevice] = []

        for deviceID in deviceIDs {
            guard var device = queryDevice(deviceID) else { continue }
            guard device.isOutput && device.isBluetooth else { continue }
            device.volume = getVolumeForDevice(deviceID)
            newAirPods.append(device)
        }

        DispatchQueue.main.async {
            self.airpodsDevices = newAirPods
        }
        print("📱 Found \(newAirPods.count) AirPods devices")
    }

    private func queryDevice(_ deviceID: AudioObjectID) -> AudioDevice? {
        guard let name = getDeviceStringProperty(deviceID, selector: kAudioObjectPropertyName) else {
            return nil
        }
        guard let uid = getDeviceStringProperty(deviceID, selector: kAudioDevicePropertyDeviceUID) else {
            return nil
        }

        let hasOutput = deviceHasBuffersInScope(deviceID, scope: kAudioObjectPropertyScopeOutput)
        let transport = getDeviceUInt32Property(deviceID, selector: kAudioDevicePropertyTransportType) ?? 0

        return AudioDevice(
            id: deviceID,
            uid: uid,
            name: name,
            isOutput: hasOutput,
            transportType: transport
        )
    }

    private func getSubDeviceIDs(_ aggregateDeviceID: AudioObjectID) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyActiveSubDeviceList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(aggregateDeviceID, &address, 0, nil, &dataSize)
        if status != noErr {
            address.mSelector = kAudioAggregateDevicePropertyFullSubDeviceList
            status = AudioObjectGetPropertyDataSize(aggregateDeviceID, &address, 0, nil, &dataSize)
            guard status == noErr else { return [] }
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }

        var subDeviceIDs = [AudioObjectID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(aggregateDeviceID, &address, 0, nil, &dataSize, &subDeviceIDs)
        guard status == noErr else { return [] }

        return subDeviceIDs
    }

    // MARK: - Volume Control

    func setVolume(for device: AudioDevice, volume: Float) {
        if let index = airpodsDevices.firstIndex(where: { $0.id == device.id }) {
            airpodsDevices[index].volume = volume
        }
        setVolumeForDevice(device.id, volume: volume)
        print("🔊 Set volume for \(device.name) to \(Int(volume * 100))%")
    }

    private func getVolumeForDevice(_ deviceID: AudioObjectID) -> Float {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var volume: Float = 1.0
        var size = UInt32(MemoryLayout<Float>.size)
        var status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
        if status != noErr {
            address.mElement = 1
            status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
        }
        return status == noErr ? volume : 1.0
    }

    private func setVolumeForDevice(_ deviceID: AudioObjectID, volume: Float) {
        var vol = volume
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var status = AudioObjectSetPropertyData(deviceID, &address, 0, nil,
                                                 UInt32(MemoryLayout<Float>.size), &vol)
        if status != noErr {
            address.mElement = 1
            status = AudioObjectSetPropertyData(deviceID, &address, 0, nil,
                                                 UInt32(MemoryLayout<Float>.size), &vol)
            if status == noErr {
                address.mElement = 2
                AudioObjectSetPropertyData(deviceID, &address, 0, nil,
                                           UInt32(MemoryLayout<Float>.size), &vol)
            }
        }
    }

    // MARK: - Default Device

    private func getCurrentDefaultOutputDevice() -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioObjectID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                   &address, 0, nil, &size, &deviceID)
        return deviceID
    }

    private func setDefaultOutputDevice(_ deviceID: AudioObjectID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var devID = deviceID
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                   &address, 0, nil,
                                   UInt32(MemoryLayout<AudioObjectID>.size), &devID)
    }

    // MARK: - Property Helpers

    private func getDeviceStringProperty(_ deviceID: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
        guard status == noErr else { return nil }
        return name as String
    }

    private func getDeviceUInt32Property(_ deviceID: AudioObjectID, selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private func deviceHasBuffersInScope(_ deviceID: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        guard status == noErr, size > 0 else { return false }

        let bufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferListPointer.deallocate() }

        let getStatus = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferListPointer)
        guard getStatus == noErr else { return false }

        let bufferList = bufferListPointer.assumingMemoryBound(to: AudioBufferList.self).pointee
        return bufferList.mNumberBuffers > 0
    }

    // MARK: - Device List Listener

    private func installDeviceListListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.refreshDevices()
        }
        self.deviceListListenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
    }

    private func removeDeviceListListener() {
        guard let block = deviceListListenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
    }

    // MARK: - Default Device Listener (Bi-directional sync)

    private func installDefaultDeviceListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleDefaultDeviceChanged()
        }
        self.defaultDeviceListenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
    }

    private func removeDefaultDeviceListener() {
        guard let block = defaultDeviceListenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
    }

    private func handleDefaultDeviceChanged() {
        guard !isUpdatingState else { return }  // Ignore changes we made ourselves
        syncStateWithSystem()
        restoreIfEnabled()
    }

    /// Sync app state with system default device
    private func syncStateWithSystem() {
        let current = getCurrentDefaultOutputDevice()

        if current == dualPodsDeviceID && !isEnabled {
            // User manually selected DualPods - enable it
            print("📍 User manually selected DualPods - enabling")
            DispatchQueue.main.async {
                self.isEnabled = true
            }
            startWatchdog()
        } else if current != dualPodsDeviceID && isEnabled {
            // User manually selected another device - disable watchdog
            print("📍 User manually selected another device - disabling")
            DispatchQueue.main.async {
                self.isEnabled = false
            }
            stopWatchdog()
        }
    }

    // MARK: - Watchdog Timer (only when enabled)

    private func startWatchdog() {
        guard watchdogTimer == nil else { return }
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.restoreIfEnabled()
        }
        print("🐕 Watchdog started")
    }

    private func stopWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        print("🐕 Watchdog stopped")
    }

    /// Restore DualPods if enabled and system switched away (watchdog + listener)
    private func restoreIfEnabled() {
        guard isEnabled else { return }
        guard dualPodsDeviceID != kAudioObjectUnknown else { return }

        let currentDefault = getCurrentDefaultOutputDevice()

        if currentDefault != dualPodsDeviceID {
            print("⚠️ Default device changed while enabled - restoring DualPods...")
            isUpdatingState = true
            setDefaultOutputDevice(dualPodsDeviceID)

            // Re-apply stored volume levels
            for device in airpodsDevices {
                setVolumeForDevice(device.id, volume: device.volume)
            }

            print("✅ DualPods restored with volumes")
            isUpdatingState = false
        }
    }
}
