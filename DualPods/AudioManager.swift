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
    var isSelected: Bool = false
    
    /// Whether this device is a multi-output/aggregate device
    var isAggregate: Bool = false
    /// Sub-device IDs (only for aggregate devices)
    var subDeviceIDs: [AudioObjectID] = []

    var isBluetooth: Bool {
        transportType == kAudioDeviceTransportTypeBluetooth ||
        transportType == kAudioDeviceTransportTypeBluetoothLE
    }
    
    var isMultiOutput: Bool {
        transportType == kAudioDeviceTransportTypeAggregate
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
    @Published var outputDevices: [AudioDevice] = []
    @Published var multiOutputDevices: [AudioDevice] = []
    @Published var activeMultiOutput: AudioDevice?
    @Published var subDevices: [AudioDevice] = []
    @Published var isActive: Bool = false
    @Published var errorMessage: String?

    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var previousDefaultDevice: AudioObjectID = kAudioObjectUnknown
    private var deviceListListenerBlock: AudioObjectPropertyListenerBlock?
    private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?

    static let aggregateDeviceName = "DualPods Multi-Output"
    static let aggregateDeviceUID = "com.dualpods.multi-output"

    init() {
        print("🔊 AudioManager initializing...")
        refreshDevices()
        installDeviceListListener()
        installDefaultDeviceListener()
    }

    deinit {
        deactivate()
        removeDeviceListListener()
        removeDefaultDeviceListener()
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

        var newOutputDevices: [AudioDevice] = []
        var newMultiOutputDevices: [AudioDevice] = []

        for deviceID in deviceIDs {
            guard var device = queryDevice(deviceID) else { continue }
            guard device.isOutput else { continue }
            // Skip our own aggregate device from the regular list
            if device.uid == Self.aggregateDeviceUID { continue }
            
            if device.isMultiOutput {
                // This is a multi-output/aggregate device - get its sub-devices
                device.isAggregate = true
                device.subDeviceIDs = getSubDeviceIDs(deviceID)
                newMultiOutputDevices.append(device)
            } else {
                device.isSelected = device.isBluetooth
                newOutputDevices.append(device)
            }
        }

        print("📱 Found \(newOutputDevices.count) output devices, \(newMultiOutputDevices.count) multi-output devices")
        if !newMultiOutputDevices.isEmpty {
            for mo in newMultiOutputDevices {
                print("   🔀 Multi-output: \(mo.name) (sub-devices: \(mo.subDeviceIDs))")
            }
        }

        DispatchQueue.main.async {
            self.outputDevices = newOutputDevices
            self.multiOutputDevices = newMultiOutputDevices
        }
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
    
    // MARK: - Sub-device enumeration
    
    private func getSubDeviceIDs(_ aggregateDeviceID: AudioObjectID) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyActiveSubDeviceList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(aggregateDeviceID, &address, 0, nil, &dataSize)
        if status != noErr {
            // Try the full sub-device list instead
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

    // MARK: - Activate Multi-Output
    
    /// Use an existing multi-output device
    func activateExisting(_ multiOutput: AudioDevice) {
        previousDefaultDevice = getCurrentDefaultOutputDevice()
        
        // Set as default output
        setDefaultOutputDevice(multiOutput.id)
        
        // Resolve sub-devices
        var resolved: [AudioDevice] = []
        for subID in multiOutput.subDeviceIDs {
            if var device = queryDevice(subID) {
                device.volume = getVolumeForDevice(subID)
                resolved.append(device)
            }
        }
        
        print("✅ Activated multi-output: \(multiOutput.name) with \(resolved.count) sub-devices")
        for dev in resolved {
            print("   🔊 \(dev.name) - volume: \(dev.volume)")
        }
        
        DispatchQueue.main.async {
            self.activeMultiOutput = multiOutput
            self.subDevices = resolved
            self.isActive = true
            self.errorMessage = nil
        }
    }
    
    /// Create a new multi-output device from selected devices
    func createAndActivate() {
        let selectedDevices = outputDevices.filter { $0.isSelected }
        guard selectedDevices.count >= 2 else {
            errorMessage = "Select at least 2 devices"
            return
        }

        // Clean up any existing DualPods aggregate device
        cleanupOrphanedAggregateDevice()
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }

        previousDefaultDevice = getCurrentDefaultOutputDevice()

        // Build sub-device list - master has no drift comp, secondaries do
        let subDevices: [[String: Any]] = selectedDevices.enumerated().map { index, device in
            [
                kAudioSubDeviceUIDKey: device.uid,
                kAudioSubDeviceDriftCompensationKey: index == 0 ? 0 : 1
            ] as [String: Any]
        }

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: Self.aggregateDeviceName,
            kAudioAggregateDeviceUIDKey: Self.aggregateDeviceUID,
            kAudioAggregateDeviceSubDeviceListKey: subDevices,
            kAudioAggregateDeviceMasterSubDeviceKey: selectedDevices[0].uid,
            kAudioAggregateDeviceIsPrivateKey: 0,
            kAudioAggregateDeviceIsStackedKey: 0
        ]

        print("🔧 Creating multi-output device...")
        var newDeviceID: AudioObjectID = kAudioObjectUnknown
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &newDeviceID)

        if status != noErr {
            print("❌ Failed: \(status)")
            errorMessage = "Failed to create multi-output device (error \(status))"
            return
        }

        print("✅ Created aggregate device: \(newDeviceID)")
        aggregateDeviceID = newDeviceID
        setDefaultOutputDevice(newDeviceID)

        // Build sub-device list for UI
        var resolved: [AudioDevice] = []
        for device in selectedDevices {
            var dev = device
            dev.volume = getVolumeForDevice(device.id)
            resolved.append(dev)
        }

        DispatchQueue.main.async {
            self.subDevices = resolved
            self.isActive = true
            self.errorMessage = nil
        }
    }

    func deactivate() {
        // Restore previous default
        if previousDefaultDevice != kAudioObjectUnknown {
            setDefaultOutputDevice(previousDefaultDevice)
        }

        // Destroy our aggregate device if we created one
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }

        DispatchQueue.main.async {
            self.isActive = false
            self.activeMultiOutput = nil
            self.subDevices = []
        }
    }

    // MARK: - Cleanup
    
    private func cleanupOrphanedAggregateDevice() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize
        )
        guard status == noErr else { return }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs
        )
        guard status == noErr else { return }
        
        for deviceID in deviceIDs {
            if let uid = getDeviceStringProperty(deviceID, selector: kAudioDevicePropertyDeviceUID),
               uid == Self.aggregateDeviceUID {
                print("🧹 Destroying orphaned aggregate device \(deviceID)")
                AudioHardwareDestroyAggregateDevice(deviceID)
            }
        }
    }

    // MARK: - Volume Control

    func setVolume(for device: AudioDevice, volume: Float) {
        if let index = subDevices.firstIndex(where: { $0.id == device.id }) {
            subDevices[index].volume = volume
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
            // Try channel 1
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
            // Try channel 1 and 2 for stereo
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

    // Note: The &name pattern triggers a Swift warning about forming UnsafeMutableRawPointer
    // to a reference type, but this is the standard CoreAudio pattern and works correctly.
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
    
    // MARK: - Default Device Listener (Fix for YouTube skip bug)
    
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
    
    /// Called when the system default output device changes
    /// If we're active and the default switched away from our multi-output, switch it back
    private func handleDefaultDeviceChanged() {
        guard isActive else { return }
        
        let currentDefault = getCurrentDefaultOutputDevice()
        
        // If we're active but the default device is not our aggregate, restore it
        if aggregateDeviceID != kAudioObjectUnknown && currentDefault != aggregateDeviceID {
            print("⚠️ Default device changed while multi-output active (YouTube skip?) - restoring...")
            setDefaultOutputDevice(aggregateDeviceID)
            
            // Re-apply stored volume levels for each sub-device
            for device in subDevices {
                setVolumeForDevice(device.id, volume: device.volume)
                print("🔊 Restored volume for \(device.name) to \(Int(device.volume * 100))%")
            }
            
            print("✅ Multi-output restored as default device with volumes")
        }
    }
}
