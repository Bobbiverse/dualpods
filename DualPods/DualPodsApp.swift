import SwiftUI

@main
struct DualPodsApp: App {
    @StateObject private var audioManager = AudioManager()
    @StateObject private var bluetoothMonitor = BluetoothMonitor()

    init() {
        print("🎧 DualPods initializing...")
        print("📊 Audio devices: \(AudioManager().outputDevices.count)")
    }

    var body: some Scene {
        MenuBarExtra("DualPods", systemImage: audioManager.isActive ? "headphones.circle.fill" : "headphones.circle") {
            ContentView(audioManager: audioManager, bluetoothMonitor: bluetoothMonitor)
        }
        .menuBarExtraStyle(.window)
    }
}
