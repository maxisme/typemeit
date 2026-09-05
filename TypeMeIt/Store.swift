import Foundation
import Observation

struct HistoryEntry: Codable, Identifiable, Sendable, Equatable {
    var id: UUID = UUID()
    var timestamp: Date
    var starred: Bool = false
    /// Engine output after local cleanup (custom words, fillers, normalisation).
    var transcript: String
    /// Apple Intelligence output; nil when off, skipped, rejected or failed.
    var postProcessed: String?
    var postProcessRequested: Bool
    var edited: String?
    var editedAt: Date?
    var durationMs: Int?
    /// Wall-clock time the speech engine took, in milliseconds.
    var transcribeMs: Int?
    /// Wall-clock time Apple Intelligence took, in milliseconds; nil when it was not requested.
    var postProcessMs: Int?
    var appId: String?
    var appName: String?
    var windowTitle: String?
    var dictionaryFixes: Int

    var displayText: String { edited ?? postProcessed ?? transcript }
}

struct LearnedWord: Codable, Identifiable, Sendable, Equatable {
    var id: UUID = UUID()
    var batchId: UUID
    var heard: String
    var meant: String
    var source: String
    var historyId: UUID?
    var learnedAt: Date
    var undone: Bool = false
}

/// history.json and learned-words.json in Application Support. Small enough
/// to hold in memory and rewrite atomically after every change.
@MainActor
@Observable
final class Store {
    static let shared = Store()

    private(set) var history: [HistoryEntry] = []
    private(set) var learned: [LearnedWord] = []

    nonisolated static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("TypeMeIt", isDirectory: true)
    }()
    private var historyURL: URL { Store.directory.appendingPathComponent("history.json") }
    private var learnedURL: URL { Store.directory.appendingPathComponent("learned-words.json") }

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {
        try? FileManager.default.createDirectory(at: Store.directory, withIntermediateDirectories: true)
        history = load(historyURL) ?? []
        learned = load(learnedURL) ?? []
    }

    private func load<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do { return try decoder.decode(T.self, from: data) } catch {
            Log.store.error("Could not read \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    private func save<T: Encodable>(_ value: T, to url: URL) {
        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            Log.store.error("Could not write \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    // MARK: History

    func append(_ entry: HistoryEntry, limit: Int) {
        history.append(entry)
        prune(limit: limit)
        save(history, to: historyURL)
    }

    func prune(limit: Int) {
        guard history.count > limit else { return }
        var excess = history.count - limit
        var kept: [HistoryEntry] = []
        for e in history {
            if excess > 0, !e.starred { excess -= 1; continue }
            kept.append(e)
        }
        history = kept
    }

    func update(_ entry: HistoryEntry) {
        guard let i = history.firstIndex(where: { $0.id == entry.id }) else { return }
        history[i] = entry
        save(history, to: historyURL)
    }

    func delete(id: UUID) {
        delete(ids: [id])
    }

    func delete(ids: Set<UUID>) {
        history.removeAll { ids.contains($0.id) }
        save(history, to: historyURL)
    }

    func deleteAllHistory() {
        history.removeAll()
        save(history, to: historyURL)
    }

    func toggleStar(id: UUID) {
        guard let i = history.firstIndex(where: { $0.id == id }) else { return }
        history[i].starred.toggle()
        save(history, to: historyURL)
    }

    func setEdited(id: UUID, text: String) {
        guard let i = history.firstIndex(where: { $0.id == id }) else { return }
        history[i].edited = text
        history[i].editedAt = Date()
        save(history, to: historyURL)
    }

    var newest: HistoryEntry? { history.last }

    // MARK: Learned words

    func appendLearned(_ words: [LearnedWord]) {
        learned.append(contentsOf: words)
        save(learned, to: learnedURL)
    }

    func undoBatch(_ batchId: UUID) -> [String] {
        var undone: [String] = []
        for i in learned.indices where learned[i].batchId == batchId && !learned[i].undone {
            learned[i].undone = true
            undone.append(learned[i].meant)
        }
        save(learned, to: learnedURL)
        return undone
    }

    /// The record behind a custom word that learning added, or nil when the
    /// user typed it in themselves.
    func learnedRecord(for word: String) -> LearnedWord? {
        learned.last { !$0.undone && $0.meant.caseInsensitiveCompare(word) == .orderedSame }
    }

    /// Marks every record for `word` undone, so that if the user adds the
    /// same word back by hand it reads as their own.
    func forgetLearned(word: String) {
        var changed = false
        for i in learned.indices where !learned[i].undone && learned[i].meant.caseInsensitiveCompare(word) == .orderedSame {
            learned[i].undone = true
            changed = true
        }
        if changed { save(learned, to: learnedURL) }
    }

    /// (heard, meant) pairs still in force, for the fuzzy matcher.
    func aliases(customWords: [String]) -> [TextCleanup.Alias] {
        let custom = Set(customWords.map { $0.lowercased() })
        return learned
            .filter { !$0.undone && custom.contains($0.meant.lowercased()) }
            .map { TextCleanup.Alias(heard: $0.heard, meant: $0.meant) }
    }
}
