import SwiftUI
import AppKit

@main
struct DualPodsApp: App {
    @StateObject private var audioManager = AudioManager()
    @StateObject private var bluetoothMonitor = BluetoothMonitor()

    init() {
        print("🎧 DualPods initializing...")
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(audioManager: audioManager, bluetoothMonitor: bluetoothMonitor)
                .frame(width: 300, height: 400)
        } label: {
            Image(systemName: "speaker.wave.2.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
