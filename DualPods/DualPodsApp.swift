import SwiftUI
import AppKit

@main
struct DualPodsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("DualPods") {
            ContentView(audioManager: appDelegate.audioManager ?? AudioManager(),
                        bluetoothMonitor: appDelegate.bluetoothMonitor ?? BluetoothMonitor())
            .frame(width: 350, height: 500)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var audioManager: AudioManager?
    var bluetoothMonitor: BluetoothMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🎧 DualPods launched via AppDelegate")

        audioManager = AudioManager()
        bluetoothMonitor = BluetoothMonitor()

        // Create the status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            // Try SF Symbol first, fall back to text
            if let img = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "DualPods") {
                img.isTemplate = true
                button.image = img
                print("✅ Status bar icon set (SF Symbol)")
            } else {
                button.title = "🎧"
                print("⚠️ SF Symbol not found, using emoji")
            }
            button.action = #selector(togglePopover)
            print("✅ Status bar button created")
        } else {
            print("❌ Failed to create status bar button")
        }

        // Create the popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 400)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: ContentView(audioManager: audioManager, bluetoothMonitor: bluetoothMonitor)
        )

        print("✅ DualPods ready - look for speaker icon in menu bar")
    }

    @objc func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
