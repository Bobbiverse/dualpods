import SwiftUI

struct ContentView: View {
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var bluetoothMonitor: BluetoothMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("DualPods")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(audioManager.isActive ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(audioManager.isActive ? "Active" : "Inactive")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 4)

            Divider()

            // Error message
            if let error = audioManager.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            // Device list
            if audioManager.outputDevices.isEmpty {
                Text("No output devices found")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                Text("Output Devices")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach($audioManager.outputDevices) { $device in
                            DeviceRow(device: $device, audioManager: audioManager)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }

            Divider()

            // Activate / Deactivate button
            Button(action: { audioManager.toggle() }) {
                HStack {
                    Image(systemName: audioManager.isActive ? "stop.circle.fill" : "play.circle.fill")
                    Text(audioManager.isActive ? "Deactivate" : "Activate Multi-Output")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(audioManager.isActive ? .red : .blue)

            // Footer buttons
            HStack {
                Button("Refresh") {
                    audioManager.refreshDevices()
                    bluetoothMonitor.refreshConnectedDevices()
                }
                .font(.caption)

                Spacer()

                Button("Quit") {
                    audioManager.deactivate()
                    NSApplication.shared.terminate(nil)
                }
                .font(.caption)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

// MARK: - Device Row

struct DeviceRow: View {
    @Binding var device: AudioDevice
    let audioManager: AudioManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle(isOn: $device.isSelected) {
                    HStack(spacing: 6) {
                        Image(systemName: device.isBluetooth ? "airpodspro" : "speaker.wave.2.fill")
                            .foregroundColor(device.isBluetooth ? .blue : .primary)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(device.name)
                                .font(.system(.body, design: .default))
                                .lineLimit(1)
                            if device.isBluetooth {
                                Text("Bluetooth")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .toggleStyle(.checkbox)
            }

            if device.isSelected {
                // Volume slider
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                    Slider(value: Binding(
                        get: { device.volume },
                        set: { newValue in
                            device.volume = newValue
                            audioManager.setVolume(for: device, volume: newValue)
                        }
                    ), in: 0...1)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                    Text("\(Int(device.volume * 100))%")
                        .font(.caption)
                        .frame(width: 36, alignment: .trailing)
                }
                .padding(.leading, 24)

                // Latency offset
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                    Slider(value: Binding(
                        get: { Double(device.latencyOffset) },
                        set: { newValue in
                            let offset = UInt32(newValue)
                            device.latencyOffset = offset
                            audioManager.setLatencyOffset(for: device, offset: offset)
                        }
                    ), in: 0...500, step: 10)
                    Text("\(device.latencyOffset)ms")
                        .font(.caption)
                        .frame(width: 44, alignment: .trailing)
                }
                .padding(.leading, 24)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(device.isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
        )
    }
}
