// Learning new vocabulary from the user's corrections.
//
// Given a transcript and the user's edited version, find the words that
// changed, keep the ones that could be vocabulary, ask the configured model
// which of those are names, products, acronyms or technical terms, and
// return the spellings to add to the custom words list. Anything that cannot
// be classified is dropped: a missed word costs the user one manual add,
// while a wrong word pollutes their dictionary.

import Foundation

/// One replacement the model will be asked about.
struct Candidate: Sendable, Equatable {
    /// What the speech model wrote.
    var heard: String
    /// What the user changed it to, with surrounding punctuation trimmed.
    var meant: String

    init(heard: String, meant: String) {
        self.heard = heard
        self.meant = meant
    }
}

/// One learned entry: what the speech model wrote and the spelling to add.
struct LearnedPair: Sendable, Equatable {
    var heard: String
    var meant: String

    init(heard: String, meant: String) {
        self.heard = heard
        self.meant = meant
    }
}

/// What the learner already knows and must not learn again.
struct LearnContext: Sendable {
    var customWords: [String]
    var denylist: [String]

    init(customWords: [String] = [], denylist: [String] = []) {
        self.customWords = customWords
        self.denylist = denylist
    }
}

enum Learning {
    /// Normalise a learned entry the way the Custom Words input does: strip
    /// `<`, `>`, `"` and `'`, then collapse runs of whitespace to one space.
    static func normalizeWord(_ word: String) -> String {
        word
            .filter { !"<>\"'".contains($0) }
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// True when `meant` is written the way English marks a proper noun inside
    /// `sentence`: a capitalised word that is not in all caps, carries no
    /// digits, and does not open a sentence. The on-device model calls
    /// invented names it has never seen "common words"; the user's
    /// capitalisation says otherwise, and the user typed it.
    static func writtenAsProperNoun(_ meant: String, in sentence: String) -> Bool {
        guard let first = meant.split(whereSeparator: \.isWhitespace).first else {
            return false
        }
        guard let initial = first.first else {
            return false
        }
        if !initial.isUppercase || first.contains(where: isASCIIDigit) {
            return false
        }
        if !first.dropFirst().contains(where: \.isLowercase) {
            return false
        }
        guard let range = sentence.firstRange(of: meant) else {
            return false
        }
        let before = sentence[..<range.lowerBound]
        guard let last = before.last(where: { !$0.isWhitespace }) else {
            return false
        }
        return !".!?:".contains(last)
    }

    /// Tokens of a multi-word replacement that are terms in their own right,
    /// for when the model judged the whole replacement a rewording because it
    /// also carried ordinary words ("NCI C D" corrected to "can CI/CD"). A
    /// token counts when it has a capital after its first letter, a slash,
    /// letters next to digits, or is unknown to the system word list.
    static func termTokens(_ meant: String) -> [String] {
        meant
            .split(whereSeparator: \.isWhitespace)
            .map { token in
                String(token.trimming { ".,;:!?()\"".contains($0) })
            }
            .filter { $0.unicodeScalars.count >= 2 }
            .filter { token in
                let hasLetters = token.unicodeScalars.contains { $0.properties.isAlphabetic }
                let innerCapital = token.dropFirst().contains(where: \.isUppercase)
                let mixedDigits = hasLetters && token.contains(where: isASCIIDigit)
                return hasLetters
                    && (innerCapital
                        || token.contains("/")
                        || mixedDigits
                        || WordList.system.isCoined(token))
            }
    }

    /// Candidates from an edit, before the model is consulted. Empty when the
    /// edit is a rewrite, too long to diff, or contains nothing learnable.
    static func candidates(original: String, edited: String, context: LearnContext) -> [Candidate] {
        guard let hunks = Prefilter.hunks(original: original, edited: edited) else {
            return []
        }
        if hunks.count > Prefilter.maxHunksPerEdit {
            return []
        }
        let known = Prefilter.keys(context.customWords)
        let denied = Prefilter.keys(context.denylist)
        var out: [Candidate] = []
        for hunk in hunks where hunk.isReplacement {
            if case .success(let candidate) = Prefilter.candidate(hunk, knownKeys: known, deniedKeys: denied) {
                out.append(candidate)
            }
            if out.count == Prefilter.maxCandidatesPerEdit {
                break
            }
        }
        return out
    }

    /// Entries to add to the dictionary after the user corrected `original`
    /// into `edited`. One model call per edit. Any failure yields nothing.
    static func learn(
        original: String,
        edited: String,
        context: LearnContext,
        check: any VocabularyCheck
    ) async -> [LearnedPair] {
        let candidates = candidates(original: original, edited: edited, context: context)
        if candidates.isEmpty {
            return []
        }
        let kinds: [CorrectionKind]
        do {
            kinds = try await check.check(candidates, context: edited)
        } catch {
            return []
        }
        var learned: [LearnedPair] = []
        func add(heard: String, meant: String) {
            let word = normalizeWord(meant)
            if !word.isEmpty && !learned.contains(where: { $0.meant == word }) {
                learned.append(LearnedPair(heard: heard, meant: word))
            }
        }
        for (candidate, kind) in zip(candidates, kinds) {
            let overridden = kind == .commonWord
                && (writtenAsProperNoun(candidate.meant, in: edited)
                    || WordList.system.isCoined(candidate.meant))
            // The model sometimes files an everyday word ("describe",
            // "cache") as a technical term. A lowercase word the system list
            // knows is one the speech model can already spell, so there is
            // nothing to learn from it.
            let ordinary = kind.isVocabulary && WordList.system.isOrdinary(candidate.meant)
            if ordinary {
                continue
            }
            if kind.isVocabulary || overridden {
                add(heard: candidate.heard, meant: candidate.meant)
            } else {
                let terms = candidate.meant.split(whereSeparator: \.isWhitespace).count > 1
                    ? termTokens(candidate.meant)
                    : []
                for term in terms {
                    add(heard: candidate.heard, meant: term)
                }
            }
        }
        return learned
    }

    private static func isASCIIDigit(_ character: Character) -> Bool {
        ("0"..."9").contains(character)
    }
}

extension Substring {
    /// Drops characters matching `predicate` from both ends, like Rust's
    /// `trim_matches`.
    func trimming(where predicate: (Character) -> Bool) -> Substring {
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
