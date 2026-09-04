import Foundation

/// Runs the learning engine on a correction, stores the result, updates the
/// custom words and shows the toast.
@MainActor
final class LearningCoordinator {
    static let shared = LearningCoordinator()
    private init() {}

    private var settings: Settings { Settings.shared }
    private var store: Store { Store.shared }

    func learn(original: String, edited: String, source: String, historyId: UUID?) {
        guard settings.learnFromCorrections else { return }
        guard case .available = PostProcessor.availability else { return }
        let context = LearnContext(customWords: settings.customWords, denylist: settings.undoneWords)
        Task { [weak self] in
            let pairs = await Learning.learn(original: original, edited: edited, context: context, check: AppleIntelligenceCheck())
            guard let self, !pairs.isEmpty else { return }
            self.apply(pairs, source: source, historyId: historyId)
        }
    }

    private func apply(_ pairs: [LearnedPair], source: String, historyId: UUID?) {
        let batch = UUID()
        var words: [String] = []
        var records: [LearnedWord] = []
        for p in pairs {
            settings.addCustomWord(p.meant)
            words.append(p.meant)
            records.append(LearnedWord(batchId: batch, heard: p.heard, meant: p.meant, source: source, historyId: historyId, learnedAt: Date()))
        }
        store.appendLearned(records)
        Log.learning.info("Learned \(words.count) word(s) from \(source)")
        Pipeline.shared.showLearnedToast(batchId: batch, words: words)
    }

    func undo(batchId: UUID) {
        let undone = store.undoBatch(batchId)
        for w in undone {
            settings.removeCustomWord(w)
            if !settings.undoneWords.contains(where: { $0.caseInsensitiveCompare(w) == .orderedSame }) {
                settings.undoneWords.append(w)
            }
        }
        Log.learning.info("Undid \(undone.count) learned word(s)")
    }
}
