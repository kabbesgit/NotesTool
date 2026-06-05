import Foundation
import AppKit

/// A held key combination: a set of modifiers plus an optional non-modifier key.
/// `modifiers` stores the raw value of the relevant `NSEvent.ModifierFlags`
/// (command/option/control/shift only). `keyCode` is the hardware key code so
/// matching is keyboard-layout independent; `display` is a human glyph string (e.g. "⌃⌥T").
struct ChordKey: Codable, Equatable {
    var modifiers: UInt
    var keyCode: UInt16?
    var display: String

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }
    var isEmpty: Bool { modifiers == 0 && keyCode == nil }
}

/// Content kind for a note item. Only markdown is rendered today; the enum is the
/// single extension point for future image/url support.
enum NoteKind: String, Codable {
    case markdown
}

struct NoteItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var kind: NoteKind = .markdown
    var content: String = ""
}

/// A named note bound to a chord. Holding the chord shows all `items`.
struct ChordNote: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = "Untitled"
    var chord: ChordKey
    var items: [NoteItem] = []
}
