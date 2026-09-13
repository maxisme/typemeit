import Foundation

/// The digits writing style: spelled-out numbers become figures. Kept apart
/// from the other styles because the number parser and its exceptions are
/// most of the code; `WritingStyle.digits` is the only caller.
enum Digits {
    private static let units: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]
    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]
    private static let ordinals: [String: Int] = [
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9,
        "tenth": 10, "eleventh": 11, "twelfth": 12, "thirteenth": 13, "fourteenth": 14, "fifteenth": 15, "sixteenth": 16,
        "seventeenth": 17, "eighteenth": 18, "nineteenth": 19, "twentieth": 20, "thirtieth": 30, "fortieth": 40,
        "fiftieth": 50, "sixtieth": 60, "seventieth": 70, "eightieth": 80, "ninetieth": 90,
    ]
    private static let scales: [String: Int] = ["hundred": 100, "thousand": 1_000, "million": 1_000_000, "billion": 1_000_000_000]

    /// "one" that is a pronoun rather than a count stays a word.
    private static let pronounOneBefore: Set<String> = ["no", "any", "every", "some", "which", "this", "that", "the", "each", "another", "other", "last", "next", "new", "wrong", "right", "good", "bad", "big", "small", "little", "old", "second", "an", "same", "different", "only", "easy", "hard", "cheap", "free", "red", "blue", "green", "black", "white", "yellow", "pink", "purple", "orange", "grey", "gray", "brown", "first", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth"]
    private static let pronounOneAfter: Set<String> = ["of", "another", "day", "another's"]

    private struct Token { var text: String; var word: String; var isWord: Bool }

    /// Rewrites every spelled-out number as digits: "twenty five" and
    /// "twenty-five" → 25, "one hundred and twenty" → 120, "first" → 1st,
    /// "one" → 1 except as a pronoun ("no one", "one of them"). "a" and "an"
    /// are untouched except before hundred, thousand or million ("a hundred"
    /// → 100), "second" stays a word since it is also a unit of time unless
    /// it follows the, my, his or the like and a word follows it,
    /// a sentence-opening "First," or the counters of a spoken list stay
    /// words, "N percent" becomes N%, "five thirty" becomes 5:30, and digits
    /// read out one at a time ("oh seven seven one…") become one number.
    static func apply(_ text: String) -> String {
        let tokens = tokenise(text)
        let listCounters = WritingStyle.counters(in: text).map { $0.range(at: 1) }
        var out: [String] = []
        var i = 0
        var offset = 0
        while i < tokens.count {
            let location = offset
            offset += (tokens[i].text as NSString).length
            guard tokens[i].isWord, let (value, end, ordinal) = number(in: tokens, from: i) else {
                out.append(tokens[i].text); i += 1; continue
            }
            if ordinal, listCounters.contains(where: { $0.location == location }) {
                out.append(tokens[i].text); i += 1; continue
            }
            let words = tokens[i..<end].filter(\.isWord)
            if words.count == 1, words[0].word == "one", isPronounOne(tokens, at: i) {
                out.append(tokens[i].text); i += 1; continue
            }
            if ordinal, words.count == 1, isCounter(tokens, at: i, end: end) {
                out.append(tokens[i].text); i += 1; continue
            }
            out.append(ordinal ? ordinalString(value) : String(value))
            i = end
        }
        var joined = out.joined()
            .replacingOccurrences(of: #"(?i)\b(?:oh|o)\b(?= \d)"#, with: "0", options: .regularExpression)
            .replacingOccurrences(of: #"(?<=\d )(?i)\b(?:oh|o)\b"#, with: "0", options: .regularExpression)
        // Digits read out one at a time, four or more of them, are one number.
        if let re = try? NSRegularExpression(pattern: #"\b\d(?: \d){3,}\b"#) {
            for m in re.matches(in: joined, range: NSRange(joined.startIndex..., in: joined)).reversed() {
                let r = Range(m.range, in: joined)!
                joined.replaceSubrange(r, with: joined[r].replacingOccurrences(of: " ", with: ""))
            }
        }
        return joined
            .replacingOccurrences(of: #"(\d) ?percent\b"#, with: "$1%", options: .regularExpression)
            .replacingOccurrences(of: #"\b(1[0-2]|[1-9]) ([0-5]\d)\b"#, with: "$1:$2", options: .regularExpression)
    }

    private static func tokenise(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        func flush() {
            guard !current.isEmpty else { return }
            let lower = current.lowercased()
            tokens.append(Token(text: current, word: lower, isWord: true))
            current = ""
        }
        for ch in text {
            if ch.isLetter { current.append(ch) } else { flush(); tokens.append(Token(text: String(ch), word: String(ch), isWord: false)) }
        }
        flush()
        return tokens
    }

    /// "First, we wait" counts a point rather than a place: an ordinal that
    /// opens a sentence, or is followed by a comma without a verb of placing
    /// before it, stays a word.
    private static let placing: Set<String> = ["came", "come", "comes", "finished", "placed", "ranked", "was", "were", "is", "are", "got"]
    private static func isCounter(_ tokens: [Token], at i: Int, end: Int) -> Bool {
        let before = tokens[..<i].last { $0.isWord || !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        let opensSentence = before == nil || (!before!.isWord && ".!?:;\n".contains(before!.text)) || before!.word == "and"
        let next = tokens[end...].first { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }?.text
        let placed = before.map { $0.isWord && placing.contains($0.word) } ?? false
        return opensSentence || next == "," && !placed
    }

    private static func isPronounOne(_ tokens: [Token], at i: Int) -> Bool {
        let before = tokens[..<i].last(where: \.isWord)?.word
        let after = tokens[(i + 1)...].first(where: \.isWord)?.word
        if let before, pronounOneBefore.contains(before) { return true }
        if let after, pronounOneAfter.contains(after) { return true }
        return false
    }

    /// Parses the longest run of number words starting at `i`, joined by
    /// single spaces, hyphens or "and" after a scale word. Returns the value,
    /// the index after the run, and whether it ended in an ordinal.
    private static func number(in tokens: [Token], from start: Int) -> (Int, Int, Bool)? {
        var i = start
        var total = 0, current = 0
        var any = false, ordinal = false
        var lastWasScale = false
        while i < tokens.count {
            let t = tokens[i]
            if !t.isWord {
                // A joiner between number words: one space or hyphen.
                if any, t.text == " " || t.text == "-", i + 1 < tokens.count, tokens[i + 1].isWord,
                   isNumberWord(tokens[i + 1].word) || (tokens[i + 1].word == "and" && lastWasScale) {
                    i += 1; continue
                }
                break
            }
            if t.word == "and" {
                guard lastWasScale, i + 2 < tokens.count, tokens[i + 1].text == " ", tokens[i + 2].isWord, isNumberWord(tokens[i + 2].word), !scales.keys.contains(tokens[i + 2].word) else { break }
                i += 1; continue
            }
            if ordinal { break }
            if t.word == "a", i + 2 < tokens.count, tokens[i + 1].text == " ", scales[tokens[i + 2].word] != nil, current == 0 {
                current = 1; any = true; lastWasScale = false
            } else if let u = units[t.word] {
                // "second" is never a number here; a repeated unit ("one two") is two numbers.
                if current % 10 != 0 || (current >= 20 && u >= 10) { break }
                current += u; any = true; lastWasScale = false
            } else if let d = tens[t.word] {
                if current != 0, current % 100 != 0 { break }
                current += d; any = true; lastWasScale = false
            } else if let o = ordinals[t.word], t.word != "second" || isOrdinalSecond(tokens, at: i) {
                if o >= 20 { if current != 0, current % 100 != 0 { break }; current += o } else {
                    if current % 10 != 0 || (current >= 20 && o >= 10) { break }
                    current += o
                }
                any = true; ordinal = true; lastWasScale = false
            } else if let s = scales[t.word] {
                guard any else { break }
                if s == 100 { current = (current == 0 ? 1 : current) * 100 } else { total += (current == 0 ? 1 : current) * s; current = 0 }
                lastWasScale = true
            } else {
                break
            }
            i += 1
        }
        guard any else { return nil }
        // Do not swallow a trailing joiner.
        while i > start, !tokens[i - 1].isWord { i -= 1 }
        return (total + current, i, ordinal)
    }

    /// "the second session" is 2nd; "a second" and "wait a second" are time.
    private static let ordinalSecondBefore: Set<String> = ["the", "my", "your", "his", "her", "our", "their", "its", "every"]
    private static func isOrdinalSecond(_ tokens: [Token], at i: Int) -> Bool {
        guard let before = tokens[..<i].last(where: \.isWord), ordinalSecondBefore.contains(before.word) else { return false }
        return tokens[(i + 1)...].first(where: \.isWord) != nil
    }

    private static func isNumberWord(_ w: String) -> Bool {
        (units[w] != nil || tens[w] != nil || scales[w] != nil || ordinals[w] != nil) && w != "second"
    }

    private static func ordinalString(_ n: Int) -> String {
        let suffix: String
        switch (n % 100, n % 10) {
        case (11...13, _): suffix = "th"
        case (_, 1): suffix = "st"
        case (_, 2): suffix = "nd"
        case (_, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }
}
