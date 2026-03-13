import SwiftUI

@main
struct DualPodsApp: App {
    @StateObject private var audioManager = AudioManager()
    @StateObject private var bluetoothMonitor = BluetoothMonitor()

    var body: some Scene {
        MenuBarExtra("DualPods", systemImage: audioManager.isActive ? "headphones.circle.fill" : "headphones.circle") {
            ContentView(audioManager: audioManager, bluetoothMonitor: bluetoothMonitor)
        }
        .menuBarExtraStyle(.window)
    }
}
