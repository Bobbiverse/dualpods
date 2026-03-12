import SwiftUI

@main
struct DualPodsApp: App {
    @StateObject private var audioManager = AudioManager()
    @StateObject private var bluetoothMonitor = BluetoothMonitor()

    var body: some Scene {
        MenuBarExtra {
            ContentView(audioManager: audioManager, bluetoothMonitor: bluetoothMonitor)
        } label: {
            Image(systemName: audioManager.isActive ? "airpodspro" : "airpods")
        }
        .menuBarExtraStyle(.window)
    }
}
