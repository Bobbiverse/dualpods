import Foundation
import IOBluetooth
import Combine

// MARK: - BluetoothMonitor

final class BluetoothMonitor: NSObject, ObservableObject {
    @Published var connectedDevices: [BluetoothDeviceInfo] = []

    struct BluetoothDeviceInfo: Identifiable, Hashable {
        let id: String // address
        let name: String
        let isAudioDevice: Bool
    }

    override init() {
        super.init()
        refreshConnectedDevices()
        registerForNotifications()
    }

    // MARK: - Device Discovery

    func refreshConnectedDevices() {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return
        }

        let devices = paired
            .filter { $0.isConnected() }
            .compactMap { device -> BluetoothDeviceInfo? in
                guard let name = device.name, let address = device.addressString else {
                    return nil
                }
                // Check if device supports A2DP (audio sink) via service records
                let isAudio = hasAudioService(device)
                return BluetoothDeviceInfo(id: address, name: name, isAudioDevice: isAudio)
            }

        DispatchQueue.main.async {
            self.connectedDevices = devices
        }
    }

    private func hasAudioService(_ device: IOBluetoothDevice) -> Bool {
        // A2DP Sink UUID: 0x110B
        // Headset UUID: 0x1108
        // HandsFree UUID: 0x111E
        let audioUUIDs: [UInt32] = [0x110B, 0x1108, 0x111E]

        guard let services = device.services as? [IOBluetoothSDPServiceRecord] else {
            // If we can't check services, assume audio if name contains known keywords
            let name = device.name?.lowercased() ?? ""
            return name.contains("airpods") || name.contains("beats") ||
                   name.contains("headphone") || name.contains("speaker") ||
                   name.contains("buds") || name.contains("audio")
        }

        for service in services {
            // Check service class ID list
            if let dict = service.attributes as? [Int: Any] {
                // Service Class ID List attribute ID = 0x0001
                // Simplified check: look for known audio UUIDs
                for (_, value) in dict {
                    if let uuid = value as? IOBluetoothSDPUUID,
                       uuid.length == 2 {
                        let bytes = uuid.bytes
                        let val = UInt32(bytes.load(as: UInt8.self)) << 8 |
                                  UInt32(bytes.advanced(by: 1).load(as: UInt8.self))
                        if audioUUIDs.contains(val) {
                            return true
                        }
                    }
                }
            }
        }

        // Fallback: check device class
        let majorClass = device.deviceClassMajor
        // Major class 0x04 = Audio/Video
        return majorClass == 0x04

    }

    // MARK: - Notifications

    private func registerForNotifications() {
        // Use IOBluetooth's native notification registration
        IOBluetoothDevice.register(forConnectNotifications: self,
                                    selector: #selector(bluetoothDeviceConnected(_:device:)))
        
        // Poll for changes periodically as a fallback
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refreshConnectedDevices()
        }
    }

    @objc private func bluetoothDeviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        refreshConnectedDevices()
        // Register for disconnect of this specific device
        device.register(forDisconnectNotification: self,
                        selector: #selector(bluetoothDeviceDisconnected(_:device:)))
    }

    @objc private func bluetoothDeviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        refreshConnectedDevices()
    }
}
