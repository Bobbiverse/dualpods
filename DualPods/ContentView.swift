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
                    .fill(audioManager.isEnabled ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(audioManager.isEnabled ? "Enabled" : "Disabled")
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
                .padding(.vertical, 4)
            }

            // Toggle button
            Button(action: {
                if audioManager.isEnabled {
                    audioManager.disable()
                } else {
                    audioManager.enable()
                }
            }) {
                HStack {
                    Image(systemName: audioManager.isEnabled ? "stop.circle.fill" : "play.circle.fill")
                    Text(audioManager.isEnabled ? "Disable DualPods" : "Enable DualPods")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(audioManager.isEnabled ? .red : .blue)

            Divider()

            // Volume controls
            Text("Volume Controls")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if audioManager.airpodsDevices.isEmpty {
                Text("No AirPods detected. Connect AirPods and restart the app.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(audioManager.airpodsDevices) { device in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "airpodspro")
                                .foregroundColor(audioManager.isEnabled ? .blue : .gray)
                            Text(device.name)
                                .font(.body)
                                .foregroundColor(audioManager.isEnabled ? .primary : .secondary)
                            Spacer()
                            Text("\(Int(device.volume * 100))%")
                                .font(.caption)
                                .foregroundColor(audioManager.isEnabled ? .secondary : Color.secondary.opacity(0.5))
                        }

                        HStack {
                            Image(systemName: "speaker")
                                .font(.caption)
                                .foregroundColor(.primary)
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
                                .foregroundColor(.primary)
                        }
                    }
                    .padding(8)
                    .background(audioManager.isEnabled ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
                    .cornerRadius(8)
                }
            }

            Spacer()

            Divider()

            // Bottom buttons
            HStack {
                Button("Refresh") {
                    audioManager.refreshDevices()
                }
                .disabled(audioManager.isEnabled)
                
                Spacer()
                
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
}
