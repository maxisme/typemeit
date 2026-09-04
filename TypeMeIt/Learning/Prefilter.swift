// Deterministic rules that decide which replacements are worth asking the
// model about. Everything the dictionary documentation says is never learned
// is dropped here, so the model only sees plausible vocabulary and a
// rewritten sentence costs one dropped edit instead of a batch of calls.
//
// The token-level diff that produces the hunks lives here too (the Rust
// `learning/diff.rs`): tokens are compared on their match key (alphanumeric,
// lowercased) so that punctuation and capitalisation differences do not
// register as changes on their own. Runs of changed tokens become hunks; a
// hunk with both a removed and an inserted side is a replacement, the only
// shape learning cares about.

import Foundation

/// One run of changed tokens between the original and the edited text.
struct Hunk: Sendable, Equatable {
    /// Tokens removed from the original, in order. Empty for a pure insertion.
    var removed: [String]
    /// Tokens inserted by the edit, in order. Empty for a pure deletion.
    var inserted: [String]

    init(removed: [String], inserted: [String]) {
        self.removed = removed
        self.inserted = inserted
    }

    var isReplacement: Bool {
        !removed.isEmpty && !inserted.isEmpty
    }
}

enum Prefilter {
    /// Most tokens on either side of a candidate.
    static let maxTokensPerSide = 4
    /// Most characters in a learned entry, matching the Custom Words input.
    static let maxMeantChars = 50
    /// Most candidates taken from a single edit.
    static let maxCandidatesPerEdit = 4
    /// More hunks than this and the edit is a rewrite, not a set of corrections.
    static let maxHunksPerEdit = 6
    /// Longest input, in tokens, that is diffed at all. Beyond this an edit is
    /// treated as a rewrite rather than a correction.
    static let maxDiffTokens = 400

    /// Speech fillers that never count as vocabulary.
    static let fillerWords: Set<String> = [
        "um", "uh", "uhm", "umm", "uhh", "uhhh", "er", "erm", "ehh", "ehm", "ahm", "hmm", "hm", "mmm",
        "like", "ah", "oh",
    ]

    /// Everyday function words. A candidate made only of these is never
    /// vocabulary, whatever the model might say.
    static let functionWords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "nor", "so", "yet", "for", "of", "to", "in", "on", "at",
        "by", "with", "from", "into", "onto", "over", "under", "about", "after", "before", "between",
        "through", "during", "without", "within", "up", "down", "out", "off", "than", "then", "as",
        "if", "because", "while", "when", "where", "why", "how", "what", "which", "who", "whom",
        "whose", "that", "this", "these", "those", "it", "its", "i", "me", "my", "mine", "we", "us",
        "our", "ours", "you", "your", "yours", "he", "him", "his", "she", "her", "hers", "they",
        "them", "their", "theirs", "is", "am", "are", "was", "were", "be", "been", "being", "do",
        "does", "did", "done", "have", "has", "had", "will", "would", "shall", "should", "can",
        "could", "may", "might", "must", "not", "no", "yes", "very", "just", "also", "too", "only",
        "even", "still", "there", "here", "now", "some", "any", "all", "each", "every", "both", "few",
        "many", "much", "more", "most", "other", "another", "such", "own", "same", "ok", "okay",
        "please", "thanks",
    ]

    /// Why a replacement was not turned into a candidate.
    enum Dropped: Error, Sendable, Equatable {
        case tooLong
        case filler
        case functionWords
        case alreadyKnown
        case denied
    }

    // MARK: Diff

    /// Lowercased alphanumeric characters of `token`, the same key the custom
    /// words matcher uses.
    static func matchKey(_ token: String) -> String {
        var key = ""
        for scalar in token.unicodeScalars where isAlphanumeric(scalar) {
            key += String(scalar).lowercased()
        }
        return key
    }

    private static func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// All hunks between `original` and `edited`, or nil when either side is
    /// too long to diff. Classic LCS over match keys; when a token can be
    /// taken from either side, the removal comes first.
    static func hunks(original: String, edited: String) -> [Hunk]? {
        let a = tokens(original)
        let b = tokens(edited)
        if a.count > maxDiffTokens || b.count > maxDiffTokens {
            return nil
        }
        let ka = a.map(matchKey)
        let kb = b.map(matchKey)

        let n = ka.count
        let m = kb.count
        let width = m + 1
        var lcs = [Int](repeating: 0, count: (n + 1) * width)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i * width + j] = ka[i] == kb[j]
                    ? lcs[(i + 1) * width + j + 1] + 1
                    : max(lcs[(i + 1) * width + j], lcs[i * width + j + 1])
            }
        }

        var out: [Hunk] = []
        var current: Hunk?
        var i = 0
        var j = 0
        while i < n || j < m {
            let matched = i < n && j < m && ka[i] == kb[j]
            if matched {
                if let hunk = current {
                    out.append(hunk)
                    current = nil
                }
                i += 1
                j += 1
                continue
            }
            if current == nil {
                current = Hunk(removed: [], inserted: [])
            }
            let takeFromA = j >= m || (i < n && lcs[(i + 1) * width + j] >= lcs[i * width + j + 1])
            if takeFromA {
                current?.removed.append(a[i])
                i += 1
            } else {
                current?.inserted.append(b[j])
                j += 1
            }
        }
        if let hunk = current {
            out.append(hunk)
        }
        return out
    }

    // MARK: Rules

    /// Trim punctuation from the ends of a phrase while keeping inner marks
    /// such as `R&D`, `CI/CD` or `GPT-4`.
    static func trimOuterPunctuation(_ phrase: String) -> String {
        let outer = phrase.unicodeScalars.trimming { scalar in
            !isAlphanumeric(scalar) && scalar != "&" && scalar != "/" && scalar != "-" && scalar != "'"
        }
        let inner = outer.trimming { scalar in
            scalar == "-" || scalar == "/" || scalar == "'"
        }
        return String(inner)
    }

    private static func phraseKey(_ tokens: [String]) -> String {
        tokens.map(matchKey).joined()
    }

    private static func allIn(_ list: Set<String>, _ tokens: [String]) -> Bool {
        tokens.allSatisfy { list.contains(matchKey($0)) }
    }

    private static func anyIn(_ list: Set<String>, _ tokens: [String]) -> Bool {
        tokens.contains { list.contains(matchKey($0)) }
    }

    /// Apply the rules to one replacement hunk.
    static func candidate(
        _ hunk: Hunk,
        knownKeys: [String],
        deniedKeys: [String]
    ) -> Result<Candidate, Dropped> {
        if hunk.removed.count > maxTokensPerSide || hunk.inserted.count > maxTokensPerSide {
            return .failure(.tooLong)
        }
        let meant = trimOuterPunctuation(hunk.inserted.joined(separator: " "))
        let heard = trimOuterPunctuation(hunk.removed.joined(separator: " "))
        if meant.unicodeScalars.count > maxMeantChars || meant.isEmpty || heard.isEmpty {
            return .failure(.tooLong)
        }
        if anyIn(fillerWords, hunk.inserted) {
            return .failure(.filler)
        }
        if allIn(functionWords, hunk.inserted) {
            return .failure(.functionWords)
        }
        let key = phraseKey(hunk.inserted)
        if knownKeys.contains(key) {
            return .failure(.alreadyKnown)
        }
        if deniedKeys.contains(key) {
            return .failure(.denied)
        }
        return .success(Candidate(heard: heard, meant: meant))
    }

    /// Match keys for a list of words or phrases, for `knownKeys` and
    /// `deniedKeys`.
    static func keys(_ words: [String]) -> [String] {
        words
            .map { word in
                word.split(whereSeparator: \.isWhitespace).map { matchKey(String($0)) }.joined()
            }
            .filter { !$0.isEmpty }
    }

    /// Unicode `Alphabetic` or `Numeric`, matching Rust's `char::is_alphanumeric`.
    static func isAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isAlphabetic || scalar.properties.numericType != nil
    }
}

extension String.UnicodeScalarView {
    /// Drops scalars matching `predicate` from both ends, like Rust's
    /// `trim_matches`.
    func trimming(where predicate: (Unicode.Scalar) -> Bool) -> SubSequence {
        self[...].trimming(where: predicate)
    }
}

extension Substring.UnicodeScalarView {
    func trimming(where predicate: (Unicode.Scalar) -> Bool) -> Substring.UnicodeScalarView {
        var result = self
        while let first = result.first, predicate(first) {
            result.removeFirst()
        }
        while let last = result.last, predicate(last) {
            result.removeLast()
        }
        return result
    }
}
