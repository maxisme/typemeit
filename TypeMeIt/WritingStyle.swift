import Foundation

/// Opinionated rewrites the user turns on. Off by default: the base prompt
/// keeps the words as spoken, and each of these changes something the
/// speaker did not say differently. Digits and lowercase are applied in code
/// after clean-up, because the model ignores a rule about them on the very
/// sentences it matters for; so are lists. Filler words and contractions go to the model
/// as rules, with the unambiguous fillers also cut in code. Scored by
/// Scripts/cleanup-eval with the cases that carry a `styles` field.
enum WritingStyle: String, Codable, CaseIterable, Sendable {
    case digits, lowercase, fillerWords, contractions, lists

    var label: String {
        switch self {
        case .digits: "digits"
        case .lowercase: "lowercase"
        case .fillerWords: "cut filler words"
        case .contractions: "contractions"
        case .lists: "lists"
        }
    }

    /// An example of the change, shown under the label.
    var example: String {
        switch self {
        case .digits: "one → 1"
        case .lowercase: "Hello Sam → hello sam"
        case .fillerWords: "like, you know, basically"
        case .contractions: "do not → don't"
        case .lists: "first, second → 1. 2."
        }
    }

    /// The rule as the model reads it, or nil for a style applied in code only.
    var rule: String? {
        switch self {
        case .digits, .lowercase, .lists: nil
        case .fillerWords:
            "Also delete these filler words, and only these: like, actually, sort of, kind of, wherever they add nothing (it was like really good → it was really good; it's kind of late → it's late). Keep them where they carry meaning (I like it, that kind of person). Keep every other word, including I think and I guess."
        case .contractions:
            "Use contractions wherever one exists (do not → don't, I am → I'm, it is → it's, we will → we'll)."
        }
    }

    /// The instruction block for a set of styles, in a fixed order, or nil for none.
    static func rules(_ styles: Set<WritingStyle>) -> String? {
        let on = allCases.filter { styles.contains($0) }.compactMap(\.rule)
        guard !on.isEmpty else { return nil }
        return "The user also wants these, applied to the whole transcript:\n" + on.map { "- " + $0 }.joined(separator: "\n")
    }

    /// The code-applied styles, on the cleaned text (or the raw transcript
    /// when clean-up returned nothing). Lowercase goes last so a sentence
    /// start restored by the filler cut is lowered again.
    static func apply(_ styles: Set<WritingStyle>, to text: String) -> String {
        var t = text
        if styles.contains(.fillerWords) { t = cutFillers(t) }
        if styles.contains(.lists) { t = numberedList(t) }
        if styles.contains(.digits) { t = digits(t) }
        if styles.contains(.lowercase) { t = t.lowercased() }
        return t
    }

    // MARK: Filler words

    /// Only the fillers that never carry meaning. "like", "actually", "sort
    /// of" and "kind of" are left to the model, which sees the sentence.
    private static let fillers = "you know|basically|literally|i mean"
    /// A filler set off by commas on both sides goes with both commas.
    private static let asidePattern = try! NSRegularExpression(pattern: #"(?i),\s*(\#(fillers)),\s*"#)
    private static let fillerPattern = try! NSRegularExpression(pattern: #"(?i)(^|[\s,])(\#(fillers))(,\s*|\s+|(?=[.?!,]))"#)

    static func cutFillers(_ text: String) -> String {
        var t = asidePattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        t = fillerPattern.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "$1")
        t = t.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+([.?!,])"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #",\s*,"#, with: ",", options: .regularExpression)
        t = t.replacingOccurrences(of: #"^[\s,]+"#, with: "", options: .regularExpression)
        return capitaliseSentences(t)
    }

    /// Uppercases the first letter of the text and of every sentence after a
    /// full stop, question or exclamation mark, so a cut at a sentence start
    /// does not leave it lowercase.
    static func capitaliseSentences(_ text: String) -> String {
        var out = ""
        var atStart = true
        for ch in text {
            if atStart, ch.isLetter { out.append(contentsOf: String(ch).uppercased()); atStart = false; continue }
            if ch.isLetter || ch.isNumber { atStart = false }
            if ".?!".contains(ch) { atStart = true }
            out.append(ch)
        }
        return out
    }

    // MARK: Lists

    private static let markers = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth"]
    /// A spoken counter at the start of a sentence: "First," "Secondly," "and third,".
    private static let markerPattern = try! NSRegularExpression(
        pattern: #"(?i)(?:^|(?<=[.!?:;]\s))(?:(?:and|then)\s+)?(first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth)(?:ly)?[,:]?\s+"#)

    /// "Three things. First, a. Second, b. And third, c." becomes the lead-in
    /// on one line and a numbered item per line. Needs at least two counters,
    /// in order from first; anything else is left as prose.
    static func numberedList(_ text: String) -> String {
        let ns = text as NSString
        let found = markerPattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard found.count >= 2 else { return text }
        for (n, m) in found.enumerated() where ns.substring(with: m.range(at: 1)).lowercased() != markers[n] { return text }
        var lines: [String] = []
        let lead = ns.substring(to: found[0].range.location).trimmingCharacters(in: .whitespacesAndNewlines)
        if !lead.isEmpty { lines.append(lead) }
        for (n, m) in found.enumerated() {
            let start = m.range.location + m.range.length
            let end = n + 1 < found.count ? found[n + 1].range.location : ns.length
            let item = ns.substring(with: NSRange(location: start, length: end - start)).trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append("\(n + 1). " + capitaliseSentences(item))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Digits

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
    private static let pronounOneBefore: Set<String> = ["no", "any", "every", "some", "which", "this", "that", "the", "each", "another", "other", "last", "next", "new", "wrong", "right", "good", "bad", "big", "small", "little", "old", "second", "an"]
    private static let pronounOneAfter: Set<String> = ["of", "another", "day", "another's"]

    private struct Token { var text: String; var word: String; var isWord: Bool }

    /// Rewrites every spelled-out number as digits: "twenty five" and
    /// "twenty-five" → 25, "one hundred and twenty" → 120, "first" → 1st,
    /// "one" → 1 except as a pronoun ("no one", "one of them"). "a" and "an"
    /// are untouched; "second" is only a number next to another number word
    /// or an ordinal context is not guessed, so it stays as it is.
    static func digits(_ text: String) -> String {
        let tokens = tokenise(text)
        var out: [String] = []
        var i = 0
        while i < tokens.count {
            guard tokens[i].isWord, let (value, end, ordinal) = number(in: tokens, from: i) else {
                out.append(tokens[i].text); i += 1; continue
            }
            let words = tokens[i..<end].filter(\.isWord)
            if words.count == 1, words[0].word == "one", isPronounOne(tokens, at: i) {
                out.append(tokens[i].text); i += 1; continue
            }
            out.append(ordinal ? ordinalString(value) : String(value))
            i = end
        }
        return out.joined()
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
            if let u = units[t.word] {
                // "second" is never a number here; a repeated unit ("one two") is two numbers.
                if current % 10 != 0 || (current >= 20 && u >= 10) { break }
                current += u; any = true; lastWasScale = false
            } else if let d = tens[t.word] {
                if current != 0, current % 100 != 0 { break }
                current += d; any = true; lastWasScale = false
            } else if let o = ordinals[t.word], t.word != "second" {
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
