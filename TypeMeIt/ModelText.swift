import Foundation

/// The two string operations that survive the model talking to us: reading its
/// output, and deciding whether it rewrote rather than cleaned.
enum ModelText {
    /// A learned mishearing: `heard` is a form the speech model has produced
    /// for `meant` before. Given to the model in its prompt.
    struct Alias: Sendable, Equatable {
        var heard: String
        var meant: String
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
