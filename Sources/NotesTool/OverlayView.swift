import SwiftUI

/// The floating card shown while a chord is held. Renders each item's markdown
/// inline (bold, `code`, italics, links) with preserved line breaks.
struct OverlayView: View {
    let note: ChordNote
    @ObservedObject var session: SessionStatsModel = .shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !note.name.isEmpty {
                Text(note.name).font(.headline)
                Divider()
            }
            ForEach(note.items) { item in
                markdown(content(for: item))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { if note.hasSession { session.refreshIfNeeded() } }
        .padding(16)
        .frame(width: 380, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.12)))
        .overlay(alignment: .topTrailing) {
            if note.hasSession && session.loading {
                ProgressView()
                    .controlSize(.small)
                    .padding(12)
                    .transition(.opacity)
            }
        }
        .animation(.default, value: session.loading)
        .shadow(radius: 18, y: 8)
    }

    /// Session items render the live snapshot (or a loading note); markdown items
    /// render their own stored content.
    private func content(for item: NoteItem) -> String {
        guard item.kind == .session else { return item.content }
        return session.snapshot?.markdown() ?? "Reading sessions…"
    }

    private func markdown(_ s: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attr = try? AttributedString(markdown: s, options: options) {
            return Text(attr)
        }
        return Text(s)
    }
}
