import SwiftUI
import AppKit

@main
struct DualPodsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var audioManager = AudioManager()
    @StateObject private var bluetoothMonitor = BluetoothMonitor()

    var body: some Scene {
        WindowGroup("DualPods") {
            ContentView(audioManager: audioManager, bluetoothMonitor: bluetoothMonitor)
                .frame(width: 350, height: 500)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🎧 DualPods launched")

        // Create the status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            if let img = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "DualPods") {
                img.isTemplate = true
                button.image = img
                print("✅ Status bar icon set (SF Symbol)")
            } else {
                button.title = "🎧"
                print("⚠️ SF Symbol not found, using emoji")
            }
            print("✅ Status bar button created")
        }

        print("✅ DualPods ready")
    }
}
