import Foundation
import SwiftUI

/// Live, computed stats for the `.session` note kind. Everything here is derived
/// purely from local `~/.claude` data — transcripts under `projects/` plus
/// `settings.json` — so the app stays self-contained (no statusline bridge).
///
/// Plan/rate-limit usage is intentionally absent: it is server-side and never
/// written to transcripts, so it cannot be reconstructed here.
struct SessionSnapshot {
    /// One recently-active Claude session.
    struct Active {
        let project: String   // basename of the session's cwd
        let model: String     // friendly model name, e.g. "Opus 4.8"
        let contextPct: Int    // estimated % of the context window in use
    }
    var active: [Active] = []
    var effort: String = "—"
    var tokensToday: Int = 0
    var tokensWeek: Int = 0
    var generatedAt: Date = .distantPast

    /// Inline-markdown card body (bold/`code` only — matches OverlayView's parser,
    /// which ignores block syntax like headings).
    func markdown() -> String {
        var lines = ["**Claude usage**"]
        lines.append("Effort: **\(effort)**")
        lines.append("Tokens: **\(Self.fmt(tokensToday))** today · **\(Self.fmt(tokensWeek))** week")
        if active.isEmpty {
            lines.append("No active sessions (last 2h)")
        } else {
            let pcts = active.map(\.contextPct)
            let avg = pcts.reduce(0, +) / pcts.count
            let peak = pcts.max() ?? 0
            lines.append("Active: **\(active.count)** sessions · ctx avg **\(avg)%** · peak **\(peak)%**")
            // Aggregate by model rather than listing each session.
            let byModel = Dictionary(grouping: active, by: \.model)
                .map { (model: $0.key, count: $0.value.count) }
                .sorted { $0.count != $1.count ? $0.count > $1.count : $0.model < $1.model }
            let summary = byModel.map { "\($0.model) **×\($0.count)**" }.joined(separator: " · ")
            lines.append(summary)
        }
        return lines.joined(separator: "\n")
    }

    static func fmt(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...:     return String(format: "%.0fk", Double(n) / 1_000)
        default:           return "\(n)"
        }
    }
}

/// Performs the (blocking) filesystem scan. Call off the main thread.
enum SessionReader {
    /// Files older than this aren't read at all (token totals only span a week).
    private static let weekWindow: TimeInterval = 7 * 24 * 3600
    /// A session counts as "active" if its last entry is within this window.
    private static let activeWindow: TimeInterval = 2 * 3600
    /// Conservative default context window; all current Claude models are ≥ this.
    private static let contextWindow = 200_000

    private static var claudeDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
    }

    static func snapshot() -> SessionSnapshot {
        var snap = SessionSnapshot()
        snap.generatedAt = Date()
        snap.effort = readEffort()

        let now = Date()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        // Timestamps in transcripts are UTC ISO-8601, which sort lexicographically —
        // so window checks are cheap string comparisons against these boundaries.
        let todayStart = iso.string(from: Calendar.current.startOfDay(for: now))
        let weekStart = iso.string(from: now.addingTimeInterval(-weekWindow))
        let activeStart = iso.string(from: now.addingTimeInterval(-activeWindow))

        let fm = FileManager.default
        let projects = claudeDir.appendingPathComponent("projects", isDirectory: true)
        guard let dirs = try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil) else {
            return snap
        }

        var freshCache: [URL: CachedFile] = [:]
        for dir in dirs {
            guard let files = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                let mod = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                if now.timeIntervalSince(mod) > weekWindow { continue }
                // Reuse the parse if the file hasn't changed since we last read it.
                // Transcripts are append-only, so an unchanged mtime means identical
                // bytes — and most week-old files don't change between refreshes.
                let parsed: ParsedFile
                if let cached = cache[file], cached.mod == mod {
                    parsed = cached.parsed
                } else if let p = parse(file: file) {
                    parsed = p
                } else {
                    continue
                }
                freshCache[file] = CachedFile(mod: mod, parsed: parsed)
                fold(parsed, file: file, todayStart: todayStart, weekStart: weekStart,
                     activeStart: activeStart, into: &snap)
            }
        }
        // Assigning only the files seen this pass prunes deleted/aged-out entries.
        cache = freshCache
        snap.active.sort { $0.project < $1.project }
        return snap
    }

    /// Parsed, time-window-independent summary of one transcript. Holds just enough
    /// to re-window cheaply (the today/week boundaries slide between refreshes, so
    /// per-entry tokens are kept rather than pre-summed totals).
    private struct ParsedFile {
        var entries: [(ts: String, tokens: Int)] = []
        var lastTimestamp = ""
        var lastModel: String?
        var lastCwd: String?
        var lastContext = 0
    }
    private struct CachedFile { let mod: Date; let parsed: ParsedFile }

    /// Per-file parse cache, keyed by URL and validated against mtime. Accessed only
    /// from `snapshot()`, which runs on a single serialized off-main task (see
    /// `SessionStatsModel.refreshIfNeeded`), so no further synchronization is needed.
    private static var cache: [URL: CachedFile] = [:]

    /// Single pass over one transcript, decoding each usage entry once.
    private static func parse(file: URL) -> ParsedFile? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }

        var parsed = ParsedFile()
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            // Cheap pre-filter: only assistant lines carry a usage object.
            guard line.contains("\"usage\"") else { continue }
            guard let entry = try? JSONDecoder().decode(Entry.self, from: Data(line.utf8)),
                  let usage = entry.message?.usage, let ts = entry.timestamp else { continue }

            // Genuinely-new tokens only: input + output + cache writes. Cache *reads*
            // are excluded — the cached prefix is re-served every turn, so summing
            // reads across a session counts the same tokens dozens of times and
            // inflates the headline by an order of magnitude.
            let total = (usage.input_tokens ?? 0) + (usage.output_tokens ?? 0)
                + (usage.cache_creation_input_tokens ?? 0)
            parsed.entries.append((ts: ts, tokens: total))

            if ts >= parsed.lastTimestamp {
                parsed.lastTimestamp = ts
                parsed.lastModel = entry.message?.model ?? parsed.lastModel
                parsed.lastCwd = entry.cwd ?? parsed.lastCwd
                // Context in use ≈ everything fed to the model on the last turn.
                parsed.lastContext = (usage.input_tokens ?? 0)
                    + (usage.cache_read_input_tokens ?? 0)
                    + (usage.cache_creation_input_tokens ?? 0)
            }
        }
        return parsed
    }

    /// Folds a parsed file into the snapshot for the current time windows.
    private static func fold(_ p: ParsedFile, file: URL, todayStart: String,
                             weekStart: String, activeStart: String, into snap: inout SessionSnapshot) {
        for e in p.entries {
            if e.ts >= weekStart { snap.tokensWeek += e.tokens }
            if e.ts >= todayStart { snap.tokensToday += e.tokens }
        }
        if !p.lastTimestamp.isEmpty, p.lastTimestamp >= activeStart, let model = p.lastModel {
            let project = (p.lastCwd as NSString?)?.lastPathComponent ?? file.deletingPathExtension().lastPathComponent
            let pct = min(100, Int(Double(p.lastContext) / Double(contextWindow) * 100))
            snap.active.append(.init(project: project, model: friendlyModel(model), contextPct: pct))
        }
    }

    private static func readEffort() -> String {
        let url = claudeDir.appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let effort = obj["effortLevel"] as? String else { return "—" }
        return effort
    }

    /// "claude-opus-4-8" → "Opus 4.8". Falls back to the raw id if unrecognized.
    private static func friendlyModel(_ id: String) -> String {
        var s = id
        if s.hasPrefix("claude-") { s.removeFirst("claude-".count) }
        let parts = s.split(separator: "-")
        guard let family = parts.first else { return id }
        // Version segments are 1–2 digits ("4", "8"); a longer numeric run is a
        // date suffix (e.g. "20251001" in "claude-haiku-4-5-20251001") — stop there.
        let version = parts.dropFirst()
            .prefix { $0.count <= 2 && $0.allSatisfy(\.isNumber) }
            .joined(separator: ".")
        let name = family.prefix(1).uppercased() + family.dropFirst()
        return version.isEmpty ? name : "\(name) \(version)"
    }

    /// Minimal projection of a transcript line — JSONDecoder ignores the rest.
    private struct Entry: Decodable {
        let timestamp: String?
        let cwd: String?
        let message: Message?
        struct Message: Decodable {
            let model: String?
            let usage: Usage?
        }
        struct Usage: Decodable {
            let input_tokens: Int?
            let output_tokens: Int?
            let cache_creation_input_tokens: Int?
            let cache_read_input_tokens: Int?
        }
    }
}

/// Shared, observable holder for the latest snapshot. The scan runs off-main and
/// publishes back; results are cached briefly so rapid re-holds don't rescan.
@MainActor
final class SessionStatsModel: ObservableObject {
    static let shared = SessionStatsModel()

    @Published private(set) var snapshot: SessionSnapshot?
    /// Called after a fresh snapshot lands, so the overlay can re-fit its panel.
    var onUpdate: (() -> Void)?

    private var loading = false
    private static let cacheTTL: TimeInterval = 10

    func refreshIfNeeded() {
        if let snap = snapshot, Date().timeIntervalSince(snap.generatedAt) < Self.cacheTTL {
            return
        }
        guard !loading else { return }
        loading = true
        Task.detached(priority: .userInitiated) {
            let snap = SessionReader.snapshot()
            await MainActor.run {
                self.snapshot = snap
                self.loading = false
                self.onUpdate?()
            }
        }
    }
}
