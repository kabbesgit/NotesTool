import AppKit
import ApplicationServices

/// Watches the keyboard system-wide (and locally) and reports which configured
/// chord, if any, is currently held. Only observes — never swallows — events, so
/// it relies on modifier-based chords that don't type text into the focused app.
@MainActor
final class ChordMonitor {
    var onActivate: ((ChordNote) -> Void)?
    var onDeactivate: (() -> Void)?

    private weak var store: ConfigStore?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    private var currentModifiers: NSEvent.ModifierFlags = []
    private var heldKey: UInt16?
    private var activeNoteID: UUID?

    private let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    private let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .keyUp]
    private var trustTimer: Timer?

    init(store: ConfigStore) { self.store = store }

    func start() {
        guard globalMonitor == nil else { return }
        installGlobalMonitor()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
        // Global key-down delivery requires Accessibility trust. If it isn't granted
        // yet, watch for it and re-arm the monitor the instant it is — no relaunch needed.
        if !AXIsProcessTrusted() {
            trustTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, AXIsProcessTrusted() else { return }
                    self.installGlobalMonitor()
                    self.trustTimer?.invalidate()
                    self.trustTimer = nil
                }
            }
        }
    }

    private func installGlobalMonitor() {
        if let g = globalMonitor { NSEvent.removeMonitor(g); globalMonitor = nil }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }
    }

    private func handle(_ event: NSEvent) {
        currentModifiers = event.modifierFlags.intersection(relevant)
        switch event.type {
        case .keyDown:
            if !event.isARepeat { heldKey = event.keyCode }
        case .keyUp:
            if heldKey == event.keyCode { heldKey = nil }
        case .flagsChanged:
            // Releasing all modifiers also clears any key we may have missed the keyUp for.
            if currentModifiers.isEmpty { heldKey = nil }
        default:
            break
        }
        evaluate()
    }

    private func evaluate() {
        guard let notes = store?.notes else { return }
        // Require at least one modifier (exact match) so chords stay inert while typing.
        let match = currentModifiers.isEmpty ? nil : notes.first { note in
            note.chord.modifierFlags == currentModifiers
                && (note.chord.keyCode == nil || note.chord.keyCode == heldKey)
        }
        if let match {
            if activeNoteID != match.id {
                activeNoteID = match.id
                onActivate?(match)
            }
        } else if activeNoteID != nil {
            activeNoteID = nil
            onDeactivate?()
        }
    }
}
