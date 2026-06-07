import AppKit
import SwiftUI

/// Owns the single floating, click-through, non-activating panel used to show notes.
@MainActor
final class OverlayController {
    private var panel: NSPanel?
    private var host: NSHostingView<OverlayView>?

    func show(note: ChordNote) {
        let panel = ensurePanel()
        let host = NSHostingView(rootView: OverlayView(note: note))
        self.host = host
        panel.contentView = host
        // Session content arrives asynchronously; re-fit the panel when it lands.
        SessionStatsModel.shared.onUpdate = note.hasSession ? { [weak self] in self?.fit() } : nil
        fit()
        panel.orderFrontRegardless()
    }

    func hide() {
        SessionStatsModel.shared.onUpdate = nil
        panel?.orderOut(nil)
    }

    /// Size the panel to its content and center it on the mouse's screen.
    private func fit() {
        guard let panel, let host else { return }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        panel.setContentSize(size)
        let screen = screenForMouse()
        panel.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2,
                                     y: screen.frame.midY - size.height / 2))
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 200),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.ignoresMouseEvents = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        panel = p
        return p
    }

    private func screenForMouse() -> NSScreen {
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
    }
}
