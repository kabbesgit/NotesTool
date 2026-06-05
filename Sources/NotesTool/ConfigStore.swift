import Foundation
import AppKit

/// Loads/saves notes as JSON in Application Support and publishes them to the UI.
@MainActor
final class ConfigStore: ObservableObject {
    @Published var notes: [ChordNote] = []

    let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("NotesTool", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("config.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([ChordNote].self, from: data) else {
            notes = [ConfigStore.sampleNote()]
            save()
            return
        }
        notes = decoded
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(notes) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func add(_ note: ChordNote) { notes.append(note); save() }

    func update(_ note: ChordNote) {
        if let i = notes.firstIndex(where: { $0.id == note.id }) { notes[i] = note; save() }
    }

    func delete(_ note: ChordNote) { notes.removeAll { $0.id == note.id }; save() }

    static func sampleNote() -> ChordNote {
        let mods = NSEvent.ModifierFlags([.control, .option]).rawValue
        let body = """
        ### tmux
        **prefix** = `⌃b`
        `prefix c`  new window
        `prefix ,`  rename window
        `prefix %`  split vertical
        `prefix "`  split horizontal
        `prefix d`  detach
        """
        return ChordNote(
            name: "Sample — tmux",
            chord: ChordKey(modifiers: mods, keyCode: 17 /* t */, display: "⌃⌥T"),
            items: [NoteItem(content: body)]
        )
    }
}
