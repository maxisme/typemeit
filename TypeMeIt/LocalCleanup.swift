import Foundation

/// The mechanical part of clean-up, done locally on whatever is about to be
/// typed: filler sounds, stutters and whitespace. The model is asked to do
/// the same, and often does not (a tidy sentence with an unfamiliar word
/// comes back untouched), so this runs on its output and on the raw
/// transcript alike. Line breaks are kept; within a line, fillers go first
/// and stutters are judged on what is left, so "the the uh the" is one "the".
enum LocalCleanup {
    /// Filler sounds, with any elongation: "uh", "uhhh", "ummm", "erm",
    /// "hmm". "mm" is millimetres, so m needs three.
    nonisolated(unsafe) static let filler = /^(?:u+h+m*|u+m+|a+h+m*|e+h+m*|e+r+m*|h+m+|m{3,}|ha)$/

    static func isFillerSound(_ word: String) -> Bool { word.lowercased().wholeMatch(of: filler) != nil }

    /// Repeats of a bare alphabetic word at or above this count collapse to
    /// one ("I I I think" → "I think"). Two is deliberate speech ("very
    /// very"); punctuated repeats ("No. No. No,") are too.
    static let stutterRun = 3

    static func run(_ text: String) -> String {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { line(String($0)) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .newlines)
    }

    private static func line(_ text: String) -> String {
        let tokens = text.unicodeScalars.split(whereSeparator: { $0.properties.isWhitespace }).map { Token(String($0)) }
        var words: [Token] = []
        for (n, t) in tokens.enumerated() {
            // "uh oh" is a phrase, not a hesitation.
            let uhOh = t.suffix.isEmpty && t.key.wholeMatch(of: /u+h+/) != nil && n + 1 < tokens.count && tokens[n + 1].key == "oh"
            guard isFiller(t), !uhOh else { words.append(t); continue }
            // A filler ending a sentence ("that's it um.") hands the stop back.
            if t.suffix == ".", let last = words.last, last.suffix.isEmpty {
                words[words.count - 1] = Token(prefix: last.prefix, core: last.core, suffix: ".")
            }
        }
        var out: [Token] = []
        var i = 0
        while i < words.count {
            let t = words[i]
            var run = 1
            if t.isBareWord {
                while i + run < words.count, words[i + run].key == t.key, words[i + run].prefix.isEmpty,
                      words[i + run - 1].suffix.isEmpty { run += 1 }
            }
            if run >= stutterRun {
                out.append(Token(prefix: t.prefix, core: t.core, suffix: words[i + run - 1].suffix))
            } else {
                out.append(t)
                run = 1
            }
            i += run
        }
        return out.map(\.text).joined(separator: " ")
    }

    /// A filler goes with the comma or full stop it carries. One ending in
    /// "?" or "!" is an interjection ("eh?"), and one opening a quote or
    /// bracket would leave it unbalanced; both stay.
    private static func isFiller(_ t: Token) -> Bool {
        isFillerSound(t.core) && t.prefix.isEmpty && ["", ",", "."].contains(t.suffix)
    }

    struct Token {
        let prefix: String
        let core: String
        let suffix: String

        init(prefix: String, core: String, suffix: String) {
            self.prefix = prefix; self.core = core; self.suffix = suffix
        }

        init(_ word: String) {
            let s = Array(word.unicodeScalars)
            let start = s.firstIndex(where: Token.isWordScalar) ?? s.count
            let end = s.lastIndex(where: Token.isWordScalar).map { $0 + 1 } ?? start
            prefix = String(String.UnicodeScalarView(s[..<start]))
            core = String(String.UnicodeScalarView(s[start..<end]))
            suffix = String(String.UnicodeScalarView(s[end...]))
        }

        var key: String { core.lowercased() }
        var text: String { prefix + core + suffix }
        /// Letters only: "don't", "well-known" and numbers never collapse.
        var isBareWord: Bool { !core.isEmpty && core.unicodeScalars.allSatisfy { $0.properties.isAlphabetic } }

        private static func isWordScalar(_ c: Unicode.Scalar) -> Bool {
            let p = c.properties
            if p.isAlphabetic { return true }
            switch p.generalCategory {
            case .decimalNumber, .letterNumber, .otherNumber: return true
            default: return false
            }
        }
    }
}
