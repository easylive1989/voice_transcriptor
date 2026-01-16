import Cocoa
import SwiftUI

class StatusBarManager: NSObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var settingsWindow: NSWindow?

    // Callbacks
    var onQuit: (() -> Void)?

    override init() {
        super.init()
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Voice Transcriptor")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        // Construct Menu
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func updateStatus(recording: Bool, processing: Bool) {
        DispatchQueue.main.async {
            if let button = self.statusItem.button {
                if processing {
                    // Flash or show processing icon
                    button.image = NSImage(systemSymbolName: "hourglass", accessibilityDescription: "Processing")
                } else if recording {
                    // Red icon
                    let image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")
                    image?.isTemplate = false // Use original color
                    // In a real app we would tint this red manually or use symbol config
                    button.image = image
                    button.contentTintColor = .red
                } else {
                    // Idle
                    button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Idle")
                    button.contentTintColor = nil
                }
            }
        }
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        // Since we attached a menu, the action might not fire unless we handle clicks differently.
        // Standard NSStatusItem behavior: if menu is set, click shows menu.
        // We can use a custom view or Delegate if we want left click -> do something, right click -> menu.
        // For this spec, standard menu is fine.
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView()
            settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            settingsWindow?.center()
            settingsWindow?.setFrameAutosaveName("Settings")
            settingsWindow?.contentView = NSHostingView(rootView: settingsView)
            settingsWindow?.title = "Settings"
            settingsWindow?.isReleasedWhenClosed = false
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(self)
    }
}
