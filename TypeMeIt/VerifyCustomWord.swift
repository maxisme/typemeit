import Foundation
import FoundationModels
import Observation

/// After a word is added to the custom-words list, re-runs the Apple
/// Intelligence cleanup on the last few kept-audio dictations with the new
/// word in the list. Where the word now appears in the output that did not
/// have it before, the row is recorded as a "would have caught it" match so
/// the user can see the change would take next time the same audio came in.
///
/// The verification runs in its own `LanguageModelSession` rather than the
/// shared `PostProcessor`, so a dictation happening in parallel is not
/// cancelled by this check.
@MainActor
@Observable
final class VerifyCustomWord {
    static let shared = VerifyCustomWord()

    enum State: Equatable {
        case idle
        case checking(word: String, scanned: Int, total: Int)
        case done(word: String, matches: [Match], scanned: Int)
    }

    struct Match: Identifiable, Equatable, Sendable {
        let id: UUID
        let timestamp: Date
        let before: String
        let after: String
        let recordingFile: String?
    }

    /// The most recent kept-audio dictations to re-check. Verification is a
    /// side-check, not a report; a handful of recent runs is enough to
    /// answer "does this help next time".
    static let depth = 10

    private(set) var state: State = .idle
    private var task: Task<Void, Never>?

    /// Kicks off a verification for `word` against `history`. Cancels any
    /// verification in flight. A no-op when the model is unavailable, when
    /// nothing in the history kept its audio, or when the word does not
    /// pre-filter to a candidate. Existing custom words are what the pipeline
    /// currently applies; the new word is appended for the re-check.
    func run(for word: String, existingWords: [String], history: [HistoryEntry]) {
        task?.cancel()
        let normalized = word.trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else { state = .idle; return }
        guard case .available = PostProcessor.availability else { state = .idle; return }

        let lookup = normalized.lowercased()
        // Newest first; only dictations that still have audio; skip anything
        // that already contains the word (nothing to prove there).
        let candidates = history
            .reversed()
            .filter { $0.recordingFile != nil && !$0.displayText.lowercased().contains(lookup) }
            .prefix(VerifyCustomWord.depth)
            .map { $0 }

        guard !candidates.isEmpty else {
            state = .done(word: normalized, matches: [], scanned: 0)
            return
        }

        state = .checking(word: normalized, scanned: 0, total: candidates.count)
        let updatedWords = existingWords + [normalized]
        task = Task { [weak self] in
            guard let self else { return }
            var matches: [Match] = []
            var scanned = 0
            for entry in candidates {
                if Task.isCancelled { return }
                if let processed = await VerifyCustomWord.reclean(entry.transcript, customWords: updatedWords),
                   processed.lowercased().contains(lookup),
                   !VerifyCustomWord.same(processed, entry.displayText) {
                    matches.append(Match(id: entry.id, timestamp: entry.timestamp,
                                         before: entry.displayText, after: processed,
                                         recordingFile: entry.recordingFile))
                }
                scanned += 1
                if Task.isCancelled { return }
                self.state = .checking(word: normalized, scanned: scanned, total: candidates.count)
            }
            if Task.isCancelled { return }
            self.state = .done(word: normalized, matches: matches, scanned: candidates.count)
        }
    }

    func clear() {
        task?.cancel()
        task = nil
        state = .idle
    }

    /// Case-insensitive whitespace-trimmed comparison; the pipeline's own
    /// cleanup can shift whitespace and casing without changing the meaning,
    /// and those are not a "would have caught it" difference.
    private static func same(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            == b.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// One-shot Apple Intelligence cleanup with the same prompt and options
    /// the live pipeline uses, in an isolated session.
    private static func reclean(_ transcript: String, customWords: [String]) async -> String? {
        let source = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return nil }
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        guard case .available = model.availability else { return nil }
        let session = LanguageModelSession(model: model, instructions: PostProcessor.instructions)
        let prompt = PostProcessor.prompt(for: source, customWords: customWords)
        do {
            let r = try await session.respond(to: prompt,
                                              generating: PostProcessor.CleanedTranscript.self,
                                              options: GenerationOptions(sampling: .greedy))
            let out = TextCleanup.stripThinkBlock(r.content.cleanedText).trimmingCharacters(in: .whitespacesAndNewlines)
            return out.isEmpty ? nil : out
        } catch {
            return nil
        }
    }
}
