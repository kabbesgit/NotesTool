import SwiftUI
import AppKit

/// Configure window: master list of notes + detail editor.
struct ConfigView: View {
    @EnvironmentObject var store: ConfigStore
    @State private var selection: UUID?
    @State private var showMarkdownHelp = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(store.notes) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.name).fontWeight(.medium)
                        Text(note.chord.display.isEmpty ? "no chord" : note.chord.display)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(note.id)
                    .contextMenu {
                        Button(role: .destructive) { deleteNote(note.id) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onDelete { offsets in offsets.map { store.notes[$0].id }.forEach(deleteNote) }
            }
            .frame(minWidth: 200)
            .onDeleteCommand { deleteNote(selection) }
            .toolbar {
                ToolbarItem {
                    Button {
                        let new = ChordNote(name: "New note",
                                            chord: ChordKey(modifiers: 0, keyCode: nil, display: ""),
                                            items: [NoteItem()])
                        store.add(new)
                        selection = new.id
                    } label: { Image(systemName: "plus") }
                }
                ToolbarItem {
                    Button { deleteNote(selection) } label: { Image(systemName: "minus") }
                        .disabled(selection == nil)
                }
                ToolbarItem {
                    Button { showMarkdownHelp = true } label: { Image(systemName: "questionmark.circle") }
                        .help("Supported Markdown")
                }
            }
        } detail: {
            if let id = selection, store.notes.contains(where: { $0.id == id }) {
                NoteEditor(note: binding(for: id)) { deleteNote(id) }
                    .id(id)
            } else {
                Text("Select or create a note")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 680, minHeight: 460)
        .sheet(isPresented: $showMarkdownHelp) { MarkdownHelpView() }
    }

    private func deleteNote(_ id: UUID?) {
        guard let id, let note = store.notes.first(where: { $0.id == id }) else { return }
        store.delete(note)
        if selection == id { selection = nil }
    }

    private func binding(for id: UUID) -> Binding<ChordNote> {
        Binding(
            get: { store.notes.first { $0.id == id } ?? ChordNote(chord: ChordKey(modifiers: 0, keyCode: nil, display: "")) },
            set: { newValue in
                if let i = store.notes.firstIndex(where: { $0.id == id }) {
                    store.notes[i] = newValue
                    store.save()
                }
            }
        )
    }
}

private struct NoteEditor: View {
    @Binding var note: ChordNote
    var onDelete: () -> Void

    var body: some View {
        Form {
            Section("Name") {
                TextField("Name", text: $note.name)
            }
            Section("Chord") {
                ChordRecorderView(chord: $note.chord)
                Text("Hold the chord anywhere to show this note; release to hide it. Include ⌃ to stay inert in other apps.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Items") {
                ForEach($note.items) { $item in
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("Type", selection: $item.kind) {
                            Text("Markdown").tag(NoteKind.markdown)
                            Text("Claude session").tag(NoteKind.session)
                        }
                        .pickerStyle(.segmented)
                        if item.kind == .session {
                            Text("Shows live Claude session stats — model, context %, effort, and tokens today/this week. Content is generated automatically.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            TextEditor(text: $item.content)
                                .font(.system(.body, design: .monospaced))
                                .frame(minHeight: 90)
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                        }
                        HStack {
                            Spacer()
                            Button(role: .destructive) {
                                note.items.removeAll { $0.id == item.id }
                            } label: { Label("Remove", systemImage: "trash") }
                                .disabled(note.items.count <= 1)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Button {
                    note.items.append(NoteItem())
                } label: { Label("Add item", systemImage: "plus") }
            }
            Section("Preview") {
                OverlayView(note: note)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            Section {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete note", systemImage: "trash")
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Reference sheet for the markdown the overlay renders. Each example is shown as
/// raw source beside its live-rendered result, using the same inline-only parser as
/// `OverlayView` — so the preview is exactly what a chord will display. Block syntax
/// (headings, lists, quotes) is intentionally absent: the overlay parses inline only.
private struct MarkdownHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Example: Identifiable {
        let id = UUID()
        let label: String
        let source: String
    }
    private let examples = [
        Example(label: "Bold", source: "**bold**"),
        Example(label: "Italic", source: "*italic*"),
        Example(label: "Bold italic", source: "***both***"),
        Example(label: "Inline code", source: "`code`"),
        Example(label: "Strikethrough", source: "~~struck~~"),
        Example(label: "Link", source: "[label](https://example.com)"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Supported Markdown").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()
            ScrollView {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 24, verticalSpacing: 14) {
                    GridRow {
                        ForEach(["Type", "Markdown", "Preview"], id: \.self) {
                            Text($0).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(examples) { ex in
                        GridRow {
                            Text(ex.label)
                            Text(ex.source)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                            rendered(ex.source).font(.body)
                        }
                    }
                }
                .padding()
            }
            Divider()
            Text("Line breaks are preserved. Headings, lists, and block quotes are not rendered — the overlay parses inline markdown only.")
                .font(.caption).foregroundStyle(.secondary)
                .padding()
        }
        .frame(width: 480, height: 380)
    }

    private func rendered(_ s: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attr = try? AttributedString(markdown: s, options: options) {
            return Text(attr)
        }
        return Text(s)
    }
}

/// Records a held chord by capturing the union of modifiers and the last key
/// pressed, finalizing when all modifiers are released. Swallows events while
/// recording so they don't leak into the form.
private struct ChordRecorderView: View {
    @Binding var chord: ChordKey
    @State private var recording = false
    @State private var monitor: Any?
    @State private var caughtMods: NSEvent.ModifierFlags = []
    @State private var caughtKey: UInt16?
    @State private var caughtChar: String = ""

    private let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    var body: some View {
        HStack {
            Text(chord.display.isEmpty ? "—" : chord.display)
                .font(.system(.title3, design: .rounded))
                .frame(minWidth: 70, alignment: .leading)
            Spacer()
            Button(recording ? "Press chord, then release…" : "Record chord") {
                recording ? stop() : start()
            }
            if !chord.display.isEmpty {
                Button("Clear") {
                    chord = ChordKey(modifiers: 0, keyCode: nil, display: "")
                }
            }
        }
    }

    private func start() {
        caughtMods = []; caughtKey = nil; caughtChar = ""
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { event in
            let mods = event.modifierFlags.intersection(relevant)
            caughtMods.formUnion(mods)
            if event.type == .keyDown {
                caughtKey = event.keyCode
                caughtChar = Self.printableChar(event)
            }
            if event.type == .flagsChanged && mods.isEmpty && !caughtMods.isEmpty {
                finalize()
            }
            return nil
        }
    }

    private func finalize() {
        let display = Self.glyphs(caughtMods) + caughtChar.uppercased()
        chord = ChordKey(modifiers: caughtMods.rawValue, keyCode: caughtKey, display: display)
        stop()
    }

    private func stop() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    private static func printableChar(_ event: NSEvent) -> String {
        guard let c = event.charactersIgnoringModifiers, let scalar = c.unicodeScalars.first,
              scalar.value >= 32 else { return "" }
        return c
    }

    private static func glyphs(_ m: NSEvent.ModifierFlags) -> String {
        var s = ""
        if m.contains(.control) { s += "⌃" }
        if m.contains(.option) { s += "⌥" }
        if m.contains(.shift) { s += "⇧" }
        if m.contains(.command) { s += "⌘" }
        return s
    }
}
