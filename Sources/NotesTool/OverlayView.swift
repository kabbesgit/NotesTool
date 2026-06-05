import SwiftUI

/// The floating card shown while a chord is held. Renders each item's markdown
/// inline (bold, `code`, italics, links) with preserved line breaks.
struct OverlayView: View {
    let note: ChordNote

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !note.name.isEmpty {
                Text(note.name).font(.headline)
                Divider()
            }
            ForEach(note.items) { item in
                markdown(item.content)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 380, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.12)))
        .shadow(radius: 18, y: 8)
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
