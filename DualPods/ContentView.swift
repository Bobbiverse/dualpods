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

            if audioManager.isActive {
                // ACTIVE STATE: Show sub-device volume controls
                activeView
            } else {
                // INACTIVE STATE: Show multi-output devices and device selection
                inactiveView
            }

            Divider()

            // Bottom buttons
            HStack {
                Button("Refresh") {
                    audioManager.refreshDevices()
                }
                Spacer()
                if audioManager.isActive {
                    Button("Deactivate") {
                        audioManager.deactivate()
                    }
                    .foregroundColor(.red)
                }
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding()
        .onAppear {
            audioManager.refreshDevices()
        }
    }
    
    // MARK: - Active View (volume controls)
    
    var activeView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let multiOutput = audioManager.activeMultiOutput {
                Text("Playing through: \(multiOutput.name)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text("Volume Controls")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            ForEach(audioManager.subDevices) { device in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: device.isBluetooth ? "airpodspro" : "speaker.wave.2")
                            .foregroundColor(.blue)
                        Text(device.name)
                            .font(.body)
                        Spacer()
                        Text("\(Int(device.volume * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Image(systemName: "speaker")
                            .font(.caption)
                        Slider(
                            value: Binding(
                                get: { device.volume },
                                set: { newVal in
                                    audioManager.setVolume(for: device, volume: newVal)
                                }
                            ),
                            in: 0...1
                        )
                        Image(systemName: "speaker.wave.3")
                            .font(.caption)
                    }
                }
                .padding(8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            
            if audioManager.subDevices.isEmpty {
                Text("No sub-devices found")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Inactive View (device selection)
    
    var inactiveView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Existing multi-output devices
            if !audioManager.multiOutputDevices.isEmpty {
                Text("Existing Multi-Output Devices")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                ForEach(audioManager.multiOutputDevices) { device in
                    Button(action: {
                        audioManager.activateExisting(device)
                    }) {
                        HStack {
                            Image(systemName: "arrow.triangle.merge")
                                .foregroundColor(.green)
                            VStack(alignment: .leading) {
                                Text(device.name)
                                    .font(.body)
                                Text("\(device.subDeviceIDs.count) sub-devices")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("Use")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.2))
                                .cornerRadius(4)
                        }
                        .padding(8)
                        .background(Color.green.opacity(0.05))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                
                Divider()
            }
            
            // Output devices for creating new multi-output
            Text("Output Devices")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(audioManager.outputDevices) { device in
                        deviceRow(device)
                    }
                }
            }

            // Create button
            let selectedCount = audioManager.outputDevices.filter(\.isSelected).count
            Button(action: {
                audioManager.createAndActivate()
            }) {
                HStack {
                    Image(systemName: "play.circle.fill")
                    Text("Create Multi-Output (\(selectedCount) selected)")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedCount < 2)
        }
    }

    // MARK: - Device Row

    func deviceRow(_ device: AudioDevice) -> some View {
        HStack {
            Toggle(isOn: Binding(
                get: { device.isSelected },
                set: { newVal in
                    if let index = audioManager.outputDevices.firstIndex(where: { $0.id == device.id }) {
                        audioManager.outputDevices[index].isSelected = newVal
                    }
                }
            )) {
                HStack {
                    Image(systemName: device.isBluetooth ? "airpodspro" : "speaker.wave.2")
                    VStack(alignment: .leading) {
                        Text(device.name)
                        if device.isBluetooth {
                            Text("Bluetooth")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .toggleStyle(.checkbox)
        }
        .padding(.vertical, 2)
    }
}
