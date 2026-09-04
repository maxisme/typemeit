// The text side of learning from corrections made in the app TypeMeIt pasted
// into. Right after a paste lands, the focused field's value is captured
// along with the text before and after the pasted span; later reads compare
// the span between the same anchors against what was pasted. Text outside
// the anchors is never inspected. The accessibility polling session that
// drives these functions lives in another module; everything here is pure.

import Foundation

enum ReadBackText {
    /// Largest field the read-back will look at.
    static let maxFieldBytes = 200_000

    /// What surrounded the pasted text when it was captured.
    struct PasteSnapshot: Sendable, Equatable {
        var prefix: String
        var pasted: String
        var suffix: String

        init(prefix: String, pasted: String, suffix: String) {
            self.prefix = prefix
            self.pasted = pasted
            self.suffix = suffix
        }
    }

    /// Index in `text` of the scalar at UTF-16 offset `utf16`, clamped to the
    /// end of the string. An offset inside a surrogate pair rounds up to the
    /// following scalar.
    private static func index(forUTF16Offset utf16: Int, in text: String) -> String.Index {
        let scalars = text.unicodeScalars
        var units = 0
        var index = scalars.startIndex
        while index < scalars.endIndex {
            if units >= utf16 {
                return index
            }
            units += scalars[index].utf16.count
            scalars.formIndex(after: &index)
        }
        return text.endIndex
    }

    /// Locate `pasted` in `value`. When the caret position is known the
    /// occurrence ending nearest before it wins, since the caret sits at the
    /// end of a fresh paste; otherwise the last occurrence. A trailing-space
    /// variant of the paste is tried too, because TypeMeIt can append one on
    /// paste. Nil when the paste is not in the field.
    static func snapshot(value: String, pasted: String, caretUTF16: Int?) -> PasteSnapshot? {
        let scalars = value.unicodeScalars
        let needle: String
        if scalars.firstRange(of: pasted.unicodeScalars) != nil {
            needle = pasted
        } else {
            needle = String(pasted.unicodeScalars.trimmingTrailingWhitespace())
        }
        if needle.isEmpty {
            return nil
        }
        let needleScalars = needle.unicodeScalars
        let caret = caretUTF16.map { index(forUTF16Offset: $0, in: value) }
        var best: String.Index?
        var from = scalars.startIndex
        while let range = scalars[from...].firstRange(of: needleScalars) {
            let start = range.lowerBound
            let end = range.upperBound
            if let caret {
                if end <= caret {
                    best = start
                } else {
                    if best == nil {
                        best = start
                    }
                    break
                }
            } else {
                best = start
            }
            from = end
        }
        guard let start = best else {
            return nil
        }
        let end = scalars.index(start, offsetBy: needleScalars.count)
        return PasteSnapshot(
            prefix: String(scalars[..<start]),
            pasted: needle,
            suffix: String(scalars[end...])
        )
    }

    /// The text now sitting between the snapshot's anchors, or nil when the
    /// anchors no longer match: the user edited outside the pasted span, and
    /// nothing inside it can be trusted. An empty suffix anchors nothing at
    /// the end, so text typed after the paste is part of the span.
    static func currentSpan(of value: String, snapshot: PasteSnapshot) -> String? {
        let scalars = value.unicodeScalars
        let prefix = snapshot.prefix.unicodeScalars
        let suffix = snapshot.suffix.unicodeScalars
        guard scalars.starts(with: prefix) else {
            return nil
        }
        let inner = scalars[scalars.index(scalars.startIndex, offsetBy: prefix.count)...]
        guard inner.count >= suffix.count, inner.suffix(suffix.count).elementsEqual(suffix) else {
            return nil
        }
        return String(inner.dropLast(suffix.count))
    }

    /// True when `next` keeps none of the words in `previous`. Between two
    /// polls a quarter of a second apart a person cannot retype a field from
    /// scratch, so this marks a submit, a clear, or a toolkit showing its
    /// placeholder as the value. Words are compared lowercased with
    /// non-alphanumeric characters trimmed from their ends; an empty
    /// `previous` is never replaced.
    static func replacedWholesale(previous: String, next: String) -> Bool {
        func words(_ text: String) -> Set<String> {
            var set = Set<String>()
            for token in text.split(whereSeparator: \.isWhitespace) {
                let trimmed = token.unicodeScalars.trimming { !Prefilter.isAlphanumeric($0) }
                let word = String(trimmed).lowercased()
                if !word.isEmpty {
                    set.insert(word)
                }
            }
            return set
        }
        let previousWords = words(previous)
        return !previousWords.isEmpty && previousWords.isDisjoint(with: words(next))
    }
}

extension String.UnicodeScalarView {
    /// Drops trailing Unicode whitespace, like Rust's `str::trim_end`.
    func trimmingTrailingWhitespace() -> SubSequence {
        var result = self[...]
        while let last = result.last, last.properties.isWhitespace {
            result.removeLast()
        }
        return result
    }
}

/// Timings of the read-back session that watches the pasted field.
enum ReadBackTiming {
    /// Time for the paste to land before the field is first read.
    static let settle: Duration = .milliseconds(400)
    /// Web and Electron fields update their accessibility text lazily, so the
    /// pasted span is looked for repeatedly before giving up.
    static let captureAttempts = 8
    static let captureRetry: Duration = .milliseconds(300)
    /// How often the field is re-read while it has focus. Each read is kept,
    /// because some apps (Chrome) drop the element the moment focus leaves.
    static let poll: Duration = .milliseconds(250)
    /// Longest a session waits for focus to leave the field.
    static let limit: Duration = .seconds(90)
}
