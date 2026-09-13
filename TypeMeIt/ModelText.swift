import Foundation

/// The two string operations that survive the model talking to us: reading its
/// output, and deciding whether it rewrote rather than cleaned.
enum ModelText {
    /// Letters spoken one at a time are an acronym: "h q" becomes "HQ" and
    /// "p d f" becomes "PDF", so the clean-up model keeps them instead of
    /// deleting them as false starts. "a" and "I" at either end are words
    /// ("as a p d f" keeps its article), and a lone letter is left for the
    /// false-start rule.
    /// Adjacent words that spell a screen term or custom word once joined
    /// become that term: "Lottie HQ" → LottieHQ, "max retries" → MAX_RETRIES,
    /// "parse config" → parse_config. Punctuation inside the term is ignored
    /// when matching, so the spoken words need only match its letters.
    static func fuseTerms(_ text: String, terms: [String]) -> String {
        let candidates = terms.compactMap { term -> (letters: String, term: String)? in
            let letters = term.lowercased().filter { $0.isLetter || $0.isNumber }
            return letters.count >= 4 ? (letters, term) : nil
        }
        guard !candidates.isEmpty else { return text }
        let words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var out: [String] = []
        var i = 0
        while i < words.count {
            var fused = false
            for n in stride(from: min(4, words.count - i), through: 2, by: -1) {
                let slice = words[i..<(i + n)]
                let core = slice.map { $0.lowercased().filter { $0.isLetter || $0.isNumber } }.joined()
                if let hit = candidates.first(where: { $0.letters == core }) {
                    let trailing = String(slice.last!.reversed().prefix { !$0.isLetter && !$0.isNumber }.reversed())
                    out.append(hit.term + trailing)
                    i += n; fused = true; break
                }
            }
            if !fused { out.append(words[i]); i += 1 }
        }
        return out.joined(separator: " ")
    }

    /// "25 dollars" → $25, "50 pounds" → £50, "3 euros" → €3, as the prompt
    /// asks and the model rarely does.
    static func currencySymbols(_ text: String) -> String {
        text.replacingOccurrences(of: #"(?i)\b(\d[\d,]*(?:\.\d+)?) dollars?\b"#, with: "\\$$1", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\b(\d[\d,]*(?:\.\d+)?) pounds?\b"#, with: "£$1", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\b(\d[\d,]*(?:\.\d+)?) euros?\b"#, with: "€$1", options: .regularExpression)
    }

    static func joinSpelledLetters(_ text: String) -> String {
        var out: [String] = []
        var run: [String] = []
        func flush() {
            var letters = run
            var lead: [String] = [], tail: [String] = []
            while let f = letters.first, ["a", "i"].contains(f.lowercased()) { lead.append(letters.removeFirst()) }
            while let l = letters.last, ["a", "i"].contains(l.lowercased()) { tail.insert(letters.removeLast(), at: 0) }
            if letters.count >= 2 {
                out += lead; out.append(letters.joined().uppercased()); out += tail
            } else {
                out += run
            }
            run = []
        }
        for word in text.split(separator: " ", omittingEmptySubsequences: false).map(String.init) {
            if word.count == 1, word.first!.isLetter { run.append(word) } else { flush(); out.append(word) }
        }
        flush()
        return out.joined(separator: " ")
    }

    /// Strips a leading `<think>...</think>` block. Some endpoints can't disable
    /// reasoning, and some local servers put the reasoning text into `content`
    /// instead of a separate field — without this the user would get the model's
    /// chain of thought pasted along with the cleaned transcription.
    ///
    /// An unclosed block is left untouched rather than guessed at.
    static func stripThinkBlock(_ text: String) -> String {
        let open = Array("<think>".unicodeScalars)
        let close = Array("</think>".unicodeScalars)
        let scalars = Array(text.unicodeScalars)

        let start = scalars.firstIndex(where: { !isWhitespace($0) }) ?? scalars.count
        guard scalars[start...].starts(with: open) else {
            return text
        }
        let rest = scalars[(start + open.count)...]
        guard let end = firstRange(of: close, in: rest) else {
            return text
        }
        return string(rest[end.upperBound...].drop(while: isWhitespace))
    }

    /// Standard Levenshtein edit distance over Unicode scalars (strsim semantics).
    static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a.unicodeScalars)
        let b = Array(b.unicodeScalars)
        let bLen = b.count

        var cache: [Int] = Array(0..<bLen).map { $0 + 1 }
        var result = bLen

        for (i, aElem) in a.enumerated() {
            result = i + 1
            var distanceB = i

            for (j, bElem) in b.enumerated() {
                let cost = aElem != bElem ? 1 : 0
                let distanceA = distanceB + cost
                distanceB = cache[j]
                result = min(result + 1, min(distanceA, distanceB + 1))
                cache[j] = result
            }
        }

        return result
    }

    /// Drops a single trailing full stop, which the model likes to add to a
    /// sentence the user did not finish with one.
    static func stripTrailingFullStop(_ text: String) -> String {
        let trimmed = text.reversed().drop(while: { $0 == " " || $0 == "\t" || $0 == "\n" })
        guard let last = trimmed.first, last == "." else { return text }
        // Ellipsis, or any other run of dots, means something. Leave it.
        if trimmed.dropFirst().first == "." { return text }
        var scalars = Array(text.unicodeScalars)
        while let tail = scalars.last, tail == " " || tail == "\t" || tail == "\n" { scalars.removeLast() }
        if scalars.last == "." { scalars.removeLast() }
        return String(String.UnicodeScalarView(scalars))
    }

    /// `true` when the transcript carries no speech: empty, or whitespace only.
    static func isBlank(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy(isWhitespace)
    }

    // MARK: - Scalar helpers

    private static func isWhitespace(_ c: Unicode.Scalar) -> Bool {
        c.properties.isWhitespace
    }

    private static func firstRange(
        of needle: [Unicode.Scalar],
        in haystack: ArraySlice<Unicode.Scalar>
    ) -> Range<Int>? {
        guard !needle.isEmpty, haystack.count >= needle.count else {
            return nil
        }
        for start in haystack.startIndex...(haystack.endIndex - needle.count) {
            if haystack[start..<(start + needle.count)].elementsEqual(needle) {
                return start..<(start + needle.count)
            }
        }
        return nil
    }

    private static func string(_ scalars: some Sequence<Unicode.Scalar>) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }
}
