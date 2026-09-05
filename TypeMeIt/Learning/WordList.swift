// The system's English word list, used to tell a coined name from an
// ordinary word when the model cannot.

import Foundation

final class WordList: Sendable {
    /// Path of the word list on macOS (about 235k entries).
    private static let systemWordsPath = "/usr/share/dict/words"

    /// Shortest word the list is consulted for; anything shorter is too likely
    /// to be an abbreviation or a typo.
    private static let minChars = 3

    /// Common English inflections. The list holds mostly base forms, so a word
    /// counts as known when stripping one of these leaves a listed word.
    private static let suffixes = ["'s", "ies", "es", "s", "ed", "ing"]

    private let words: Set<String>

    init(words: some Sequence<String>) {
        var set = Set<String>()
        for word in words {
            let normalized = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !normalized.isEmpty {
                set.insert(normalized)
            }
        }
        self.words = set
    }

    /// The system list, read once. Empty when the file is missing, in which
    /// case nothing is ever judged coined.
    static let system: WordList = {
        let text = (try? String(contentsOfFile: systemWordsPath, encoding: .utf8)) ?? ""
        return WordList(words: text.split(whereSeparator: \.isNewline).lazy.map(String.init))
    }()

    var isEmpty: Bool {
        words.isEmpty
    }

    private func contains(_ word: String) -> Bool {
        words.contains(word)
    }

    /// True for a single alphabetic token that the list does not know in any
    /// common inflection: a name or term the user coined rather than a
    /// misspelling of, or substitute for, an ordinary word.
    func isCoined(_ term: String) -> Bool {
        guard let word = alphabeticWord(term) else {
            return false
        }
        return !knowsInAnyForm(word)
    }

    /// True for a single lowercase alphabetic token that the list knows in
    /// some common inflection: an everyday word the speech model can already
    /// spell, whatever kind the model assigned it. Capitalised words are not
    /// ordinary here, so a proper noun that happens to share its spelling
    /// with a listed word is left to the proper-noun rule.
    func isOrdinary(_ term: String) -> Bool {
        guard let word = alphabeticWord(term), term.trimmingCharacters(in: .whitespacesAndNewlines) == word else {
            return false
        }
        return knowsInAnyForm(word)
    }

    /// `term` lowercased when it is one alphabetic token of at least
    /// `minChars` and the list is loaded; nil otherwise.
    private func alphabeticWord(_ term: String) -> String? {
        if isEmpty {
            return nil
        }
        let word = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if word.unicodeScalars.count < Self.minChars
            || !word.unicodeScalars.allSatisfy({ $0.properties.isAlphabetic }) {
            return nil
        }
        return word
    }

    private func knowsInAnyForm(_ word: String) -> Bool {
        if contains(word) {
            return true
        }
        return Self.suffixes.contains { suffix in
            guard word.hasSuffix(suffix) else { return false }
            let stem = String(word.dropLast(suffix.count))
            return contains(stem)
                || (suffix == "ies" && contains(stem + "y"))
                || ((suffix == "ed" || suffix == "ing") && contains(stem + "e"))
        }
    }
}
