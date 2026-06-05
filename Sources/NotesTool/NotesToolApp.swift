import AppKit
import SwiftUI
import ApplicationServices

@main
enum Main {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

/// Owns the menu bar item, the chord monitor, the overlay, and the config window.
/// Built with AppKit (not a SwiftUI `Scene`) because `MenuBarExtra`/`Settings`
/// scenes do not reliably install when the app is a SwiftPM executable.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ConfigStore()
    let overlay = OverlayController()
    lazy var monitor = ChordMonitor(store: store)

    private var statusItem: NSStatusItem?
    private var configWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "NotesTool")

        let menu = NSMenu()
        let configItem = NSMenuItem(title: "Configure…", action: #selector(openConfig), keyEquivalent: ",")
        configItem.target = self
        let permItem = NSMenuItem(title: "Accessibility Access…", action: #selector(openAccessibility), keyEquivalent: "")
        permItem.target = self
        menu.addItem(configItem)
        menu.addItem(permItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit NotesTool", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item

        monitor.onActivate = { [weak self] note in self?.overlay.show(note: note) }
        monitor.onDeactivate = { [weak self] in self?.overlay.hide() }
        if !AXIsProcessTrusted() {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
        }
        monitor.start()
    }

    @objc private func openConfig() {
        if configWindow == nil {
            let hosting = NSHostingController(rootView: ConfigView().environmentObject(store))
            let win = NSWindow(contentViewController: hosting)
            win.title = "NotesTool Configuration"
            win.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            win.setContentSize(NSSize(width: 720, height: 500))
            win.isReleasedWhenClosed = false
            win.center()
            configWindow = win
        }
        NSApp.activate(ignoringOtherApps: true)
        configWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openAccessibility() {
        if AXIsProcessTrusted() {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        } else {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
        }
    }
}
