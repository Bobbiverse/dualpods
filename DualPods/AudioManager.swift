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
    var latencyOffset: UInt32 = 0
    var isSelected: Bool = false

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
    @Published var outputDevices: [AudioDevice] = []
    @Published var isActive: Bool = false
    @Published var errorMessage: String?

    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var previousDefaultDevice: AudioObjectID = kAudioObjectUnknown
    private var listenerBlock: AudioObjectPropertyListenerBlock?

    static let aggregateDeviceName = "DualPods Multi-Output"
    static let aggregateDeviceUID = "com.dualpods.multi-output"

    init() {
        print("🔊 AudioManager initializing...")
        refreshDevices()
        print("📱 Found \(outputDevices.count) output devices")
        installDeviceListListener()
    }

    deinit {
        deactivate()
        removeDeviceListListener()
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
        guard status == noErr else {
            print("⚠️ Failed to get device list, status: \(status)")
            return
        }
        print("🔍 CoreAudio reports \(deviceCount) total devices: \(deviceIDs)")

        let previousSelections = Dictionary(uniqueKeysWithValues: outputDevices.map { ($0.id, $0.isSelected) })
        let previousVolumes = Dictionary(uniqueKeysWithValues: outputDevices.map { ($0.id, $0.volume) })
        let previousLatencies = Dictionary(uniqueKeysWithValues: outputDevices.map { ($0.id, $0.latencyOffset) })

        var newDevices: [AudioDevice] = []
        for deviceID in deviceIDs {
            guard let device = queryDevice(deviceID) else { continue }
            // Skip our own aggregate device
            if device.uid == Self.aggregateDeviceUID { continue }
            // Only output devices
            guard device.isOutput else { continue }

            var dev = device
            dev.isSelected = previousSelections[deviceID] ?? device.isBluetooth
            dev.volume = previousVolumes[deviceID] ?? 1.0
            dev.latencyOffset = previousLatencies[deviceID] ?? 0
            newDevices.append(dev)
        }

        DispatchQueue.main.async {
            self.outputDevices = newDevices
        }
    }

    private func queryDevice(_ deviceID: AudioObjectID) -> AudioDevice? {
        guard let name = getDeviceStringProperty(deviceID, selector: kAudioObjectPropertyName) else {
            print("⚠️ Device \(deviceID): no name")
            return nil
        }
        guard let uid = getDeviceStringProperty(deviceID, selector: kAudioDevicePropertyDeviceUID) else {
            print("⚠️ Device \(deviceID) (\(name)): no UID")
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

    // MARK: - Aggregate Device Creation

    func activate() {
        let selectedDevices = outputDevices.filter { $0.isSelected }
        guard selectedDevices.count >= 2 else {
            errorMessage = "Select at least 2 devices"
            return
        }

        // Save current default output
        previousDefaultDevice = getCurrentDefaultOutputDevice()

        // Build sub-device list with latency offsets
        let subDevices: [[String: Any]] = selectedDevices.map { device in
            var subDeviceDict: [String: Any] = [
                kAudioSubDeviceUIDKey: device.uid,
                kAudioSubDeviceDriftCompensationKey: 1
            ]
            if device.latencyOffset > 0 {
                subDeviceDict["drift"] = device.latencyOffset
            }
            return subDeviceDict
        }

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: Self.aggregateDeviceName,
            kAudioAggregateDeviceUIDKey: Self.aggregateDeviceUID,
            kAudioAggregateDeviceSubDeviceListKey: subDevices,
            kAudioAggregateDeviceMasterSubDeviceKey: selectedDevices[0].uid,
            kAudioAggregateDeviceIsPrivateKey: 0,
            kAudioAggregateDeviceIsStackedKey: 0
        ]

        var newDeviceID: AudioObjectID = kAudioObjectUnknown
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &newDeviceID)

        if status != noErr {
            errorMessage = "Failed to create aggregate device (error \(status))"
            return
        }

        aggregateDeviceID = newDeviceID

        // Set as default output
        setDefaultOutputDevice(newDeviceID)

        // Apply volume settings
        for device in selectedDevices {
            setVolumeForDevice(device.id, volume: device.volume)
        }

        DispatchQueue.main.async {
            self.isActive = true
            self.errorMessage = nil
        }
    }

    func deactivate() {
        guard aggregateDeviceID != kAudioObjectUnknown else { return }

        // Restore previous default
        if previousDefaultDevice != kAudioObjectUnknown {
            setDefaultOutputDevice(previousDefaultDevice)
        }

        // Destroy aggregate device
        let status = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
        if status != noErr {
            print("Warning: Failed to destroy aggregate device (error \(status))")
        }

        aggregateDeviceID = kAudioObjectUnknown

        DispatchQueue.main.async {
            self.isActive = false
        }
    }

    func toggle() {
        if isActive {
            deactivate()
        } else {
            activate()
        }
    }

    // MARK: - Volume Control

    func setVolume(for device: AudioDevice, volume: Float) {
        if let index = outputDevices.firstIndex(where: { $0.id == device.id }) {
            outputDevices[index].volume = volume
        }
        if isActive {
            setVolumeForDevice(device.id, volume: volume)
        }
    }

    private func setVolumeForDevice(_ deviceID: AudioObjectID, volume: Float) {
        var vol = volume
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        // Try main element first, then channel 1
        var status = AudioObjectSetPropertyData(deviceID, &address, 0, nil,
                                                 UInt32(MemoryLayout<Float>.size), &vol)
        if status != noErr {
            address.mElement = 1
            status = AudioObjectSetPropertyData(deviceID, &address, 0, nil,
                                                 UInt32(MemoryLayout<Float>.size), &vol)
            // Also try channel 2 for stereo
            if status == noErr {
                address.mElement = 2
                AudioObjectSetPropertyData(deviceID, &address, 0, nil,
                                           UInt32(MemoryLayout<Float>.size), &vol)
            }
        }
    }

    // MARK: - Latency Offset

    func setLatencyOffset(for device: AudioDevice, offset: UInt32) {
        if let index = outputDevices.firstIndex(where: { $0.id == device.id }) {
            outputDevices[index].latencyOffset = offset
        }
        // Latency offset requires recreating the aggregate device
        if isActive {
            deactivate()
            activate()
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
        guard status == noErr else {
            print("⚠️ getDeviceStringProperty failed: device \(deviceID), status \(status)")
            return nil
        }
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

        // Allocate enough bytes for variable-sized AudioBufferList
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
        self.listenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
    }

    private func removeDeviceListListener() {
        guard let block = listenerBlock else { return }
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
}
