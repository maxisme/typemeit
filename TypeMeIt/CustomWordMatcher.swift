import Foundation

/// Applies the user's custom words to a transcript before the clean-up model
/// sees it. The model used to be handed the list and told to fix mishearings
/// itself; it swapped one listed word for another ("fucking lib" became
/// "typeme.it"). Here the decision is made in code and the model never sees
/// the list.
///
/// A run of one to four words is replaced by a term when
/// - its letters, ignoring case and punctuation, spell the term exactly
///   ("type me it" → typeme.it, "eliza" → Eliza), or
/// - its sound key is close to the term's, its length is close, and the
///   speech model was not sure of it. Sound similarity only nominates;
///   a word the speech model was confident in is never replaced on
///   similarity alone, since "cat" and "cut" share a sound key.
/// An exact spelling beats any sound match, and among sound matches the
/// closest wins, so "to TypeMeet" does not swallow the "to".
///
/// A confident word that sounds like a term is not replaced but reported as
/// a hint: "whisper" may be the product wispr or the quiet voice, and only
/// the sentence says which, so the clean-up model is asked to decide that
/// one word. A run that already spells a term is never replaced by another
/// term, and a run of stop words ("or", "the") is never matched by sound.
///
/// A term may carry aliases, spellings the speech model has produced for
/// it before ("Titemere" for typeme.it). A run spelling an alias counts as
/// a full sound match, so it follows the confidence rule above rather than
/// being applied blindly: the aliases come from the user's corrections and
/// some of those are wrong.
enum CustomWordMatcher {
    struct Term: Equatable, Sendable {
        let text: String
        let aliases: [String]

        init(_ text: String, aliases: [String] = []) {
            self.text = text; self.aliases = aliases
        }
    }

    /// One transcript word with how sure the speech model was of it, or
    /// nil when no confidence is known (stored history, the eval).
    struct Word: Equatable, Sendable {
        let text: String
        let confidence: Float?
    }

    /// A confident run that sounds like a term, for the model to judge.
    struct Hint: Equatable, Sendable {
        let heard: String
        let term: String
    }

    struct Outcome: Equatable {
        let text: String
        /// How many runs were replaced.
        let fixes: Int
        let hints: [Hint]

        init(text: String, fixes: Int, hints: [Hint] = []) {
            self.text = text; self.fixes = fixes; self.hints = hints
        }
    }

    static let maxRun = 4
    /// A word the speech model scored at or above this is left as heard,
    /// unless it spells the term exactly. Over 7,000 words of the user's own
    /// dictations the tenth percentile was 0.90; mishearings of names sat
    /// at 0.66 to 0.83.
    static let confidentAbove: Float = 0.9
    /// Sound keys must be at least this similar (1 - edits / longer length).
    /// Rises with the size of the list: every term that is not in the audio
    /// is a chance of a false match, so a long list has to be stricter.
    static func minSoundSimilarity(terms: Int, confidence: Float?) -> Double {
        let base: Double = terms <= 10 ? 0.75 : terms <= 100 ? 0.8 : 0.85
        // A word scored this low is nearly always a mishearing (28 of 6,963
        // correct words scored under 0.8), so a looser sound match is taken.
        if let confidence, confidence < 0.75 { return base - 0.1 }
        return base
    }
    /// Words that never stand for a term on their own: "or" is not "VR".
    static let stopWords: Set<String> = ["a", "an", "the", "and", "or", "but", "of", "to", "in", "on", "at", "by", "for", "with", "as", "is", "are", "was", "were", "be", "been", "it", "its", "this", "that", "these", "those", "i", "you", "he", "she", "we", "they", "me", "him", "her", "us", "them", "my", "your", "his", "our", "their", "so", "if", "not", "no", "yes", "do", "does", "did", "have", "has", "had", "can", "will", "would", "should", "could", "just", "then", "than", "there", "here", "what", "which", "who", "how", "when", "where", "why", "up", "out", "about", "into", "over", "also", "very", "all", "any", "some", "one", "two"]
    /// Shorter of the two compacted letter strings over the longer.
    static let minLengthRatio = 0.7
    /// Terms with fewer letters than this match only exactly: "ack" or "lib"
    /// would otherwise sit one edit from half the language.
    static let minFuzzyTermLetters = 4

    static func apply(_ words: [Word], terms: [String]) -> Outcome {
        apply(words, terms: terms.map { Term($0) })
    }

    static func apply(_ words: [Word], terms: [Term]) -> Outcome {
        let terms = terms.map { Term($0.text.trimmingCharacters(in: .whitespaces), aliases: $0.aliases.map(letters).filter { !$0.isEmpty }) }
            .filter { !letters($0.text).isEmpty }
        guard !terms.isEmpty, !words.isEmpty else {
            return Outcome(text: words.map(\.text).joined(separator: " "), fixes: 0)
        }
        let termLetters = terms.map { letters($0.text) }
        let termKeys = termLetters.map { soundKey(compact($0)) }
        let tokens = words.map { LocalCleanup.Token($0.text) }
        var out: [String] = []
        var fixes = 0
        var hints: [Hint] = []
        var i = 0
        while i < tokens.count {
            var best: (length: Int, term: String, similarity: Double)?
            for length in 1...min(maxRun, tokens.count - i) {
                let run = Array(tokens[i..<(i + length)])
                let runLetters = run.map { letters($0.core) }.joined()
                guard !runLetters.isEmpty else { continue }
                // Already one of the terms: leave it, and never trade it for another.
                if run.contains(where: { token in terms.contains { $0.text == token.core } }) { continue }
                let allStopWords = run.allSatisfy { stopWords.contains($0.key) }
                let confidences = words[i..<(i + length)].compactMap(\.confidence)
                let lowest = confidences.min()
                for (t, term) in terms.enumerated() {
                    if runLetters == termLetters[t] {
                        if best?.similarity != 2 { best = (length, term.text, 2) }
                        continue
                    }
                    guard !allStopWords else { continue }
                    var sim: Double
                    if term.aliases.contains(runLetters) {
                        sim = 1
                    } else {
                        guard termLetters[t].count >= minFuzzyTermLetters else { continue }
                        let a = compact(runLetters), b = compact(termLetters[t])
                        guard Double(min(a.count, b.count)) / Double(max(a.count, b.count)) >= minLengthRatio else { continue }
                        sim = similarity(soundKey(compact(runLetters)), termKeys[t])
                        guard sim >= minSoundSimilarity(terms: terms.count, confidence: lowest) else { continue }
                        // A leading word that adds nothing to the match belongs to
                        // the sentence, not the term: "to TypeMeet" keeps its "to".
                        if length > 1, similarity(soundKey(compact(run.dropFirst().map { letters($0.core) }.joined())), termKeys[t]) >= sim { continue }
                    }
                    if let lowest, lowest >= confidentAbove {
                        let hint = Hint(heard: run.map(\.core).joined(separator: " "), term: term.text)
                        if !hints.contains(hint) { hints.append(hint) }
                        continue
                    }
                    if sim > (best?.similarity ?? 0) { best = (length, term.text, sim) }
                }
            }
            if let best {
                let first = tokens[i], last = tokens[i + best.length - 1]
                out.append(first.prefix + best.term + last.suffix)
                fixes += 1
                i += best.length
            } else {
                out.append(tokens[i].text)
                i += 1
            }
        }
        return Outcome(text: out.joined(separator: " "), fixes: fixes, hints: hints)
    }

    /// The terms that occur in `text` as whole words, spelled as the term.
    /// The clean-up model is told to keep these; it otherwise rewrites
    /// "lib" as "library" and lowercases a name it does not know.
    static func present(in text: String, terms: [String]) -> [String] {
        let cores = Set(text.split(whereSeparator: \.isWhitespace).map { LocalCleanup.Token(String($0)).core })
        return terms.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && cores.contains($0) }
    }

    /// Lowercase letters and digits only: "typeme.it" → "typemeit".
    static func letters(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { $0.properties.isAlphabetic || $0.properties.numericType != nil })
    }

    /// Letters with doubles collapsed and a silent final e dropped, so
    /// "loti" and "lottie" compare as the same length.
    static func compact(_ letters: String) -> String {
        var out: [Character] = []
        for c in letters where out.last != c { out.append(c) }
        if out.count > 2, out.last == "e" { out.removeLast() }
        return String(out)
    }

    /// A consonant skeleton in the spirit of Metaphone, on letters only:
    /// the first letter kept, later vowels dropped, letters that sound
    /// alike merged, doubles collapsed. "typemeit" → "tpmt".
    static func soundKey(_ letters: String) -> String {
        let chars = Array(letters)
        var out: [Character] = []
        var i = 0
        while i < chars.count {
            let c = chars[i]
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            var mapped: String?
            switch c {
            case "p" where next == "h": mapped = "f"; i += 1
            case "c" where next == "k": mapped = "k"; i += 1
            case "c": mapped = ["e", "i", "y"].contains(next ?? " ") ? "s" : "k"
            case "q": mapped = "k"
            case "x": mapped = "ks"
            case "z": mapped = "s"
            case "g" where next == "h": mapped = ""; i += 1
            case "h", "w", "y": mapped = i == 0 ? String(c) : ""
            case "a", "e", "i", "o", "u": mapped = i == 0 ? String(c) : ""
            default: mapped = String(c)
            }
            for m in mapped ?? "" where out.last != m { out.append(m) }
            i += 1
        }
        return String(out)
    }

    static func similarity(_ a: String, _ b: String) -> Double {
        let longest = max(a.count, b.count)
        guard longest > 0 else { return 1 }
        return 1 - Double(ModelText.levenshtein(a, b)) / Double(longest)
    }
}
