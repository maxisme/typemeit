import Foundation

/// Opinionated rewrites the user turns on. Off by default: the base prompt
/// keeps the words as spoken, and each of these changes something the
/// speaker did not say differently. Digits are applied in code
/// after clean-up, because the model ignores a rule about them on the very
/// sentences it matters for; so are lists, quotes and the safe contractions. Filler words and contractions go to the model
/// as rules, with the unambiguous fillers also cut in code. Scored by
/// Scripts/cleanup-eval with the cases that carry a `styles` field.
enum WritingStyle: String, Codable, CaseIterable, Sendable {
    case digits, fillerWords, contractions, lists, quotes

    var label: String {
        switch self {
        case .digits: "digits"
        case .fillerWords: "cut filler words"
        case .contractions: "contractions"
        case .lists: "lists"
        case .quotes: "quotes"
        }
    }

    /// An example of the change, shown under the label.
    var example: String {
        switch self {
        case .digits: "one → 1"
        case .fillerWords: "like, you know, basically"
        case .contractions: "do not → don't"
        case .lists: "first, second → 1. 2."
        case .quotes: "she said ship it → she said \"ship it\""
        }
    }

    /// The rule as the model reads it, or nil for a style applied in code only.
    var rule: String? {
        switch self {
        case .digits, .lists, .quotes: nil
        case .fillerWords:
            "Also delete these filler words, and only these: like, actually, sort of, kind of, wherever they add nothing (it was like really good → it was really good; it's kind of late → it's late; actually I think → I think). Never delete the verb like (I like it, I do not like it) or a comparison (like rain), and never delete the words around a filler. Keep every other word, including I think and I guess."
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
    /// when clean-up returned nothing).
    static func apply(_ styles: Set<WritingStyle>, to text: String) -> String {
        var t = text
        if styles.contains(.fillerWords) { t = cutFillers(t) }
        if styles.contains(.lists) { t = numberedList(t) }
        if styles.contains(.contractions) { t = contract(t) }
        if styles.contains(.quotes) { t = quote(t) }
        if styles.contains(.digits) { t = digits(t) }
        return t
    }

    // MARK: Filler words

    /// The fillers cut in code, each with the words that make it a real
    /// phrase instead: "you know" after do, did, if; "actually" never, since
    /// as an adverb it is always a hedge; "like" only before an intensifier
    /// or at a sentence start before a pronoun, so comparisons ("like rain")
    /// and the verb ("I like it") stay. "sort of" and "kind of" are left to
    /// the model, which sees whether a noun follows.
    private static let asidePattern = try! NSRegularExpression(pattern: #"(?i),\s*(you know what i mean|you know|basically|literally|i mean|actually),\s*"#)
    private static let fillerPatterns: [NSRegularExpression] = [
        #"(?i)(^|[\s,])(you know what i mean)(,\s*|\s+|(?=[.?!,])|$)"#,
        #"(?i)(^|[\s,])(?<!\b(?:do|did|does|don't|didn't|doesn't|if|whether|as|to|let|would|could|should|will|can|must|might|i|we|they|who|that|you)\s)(you know)(,\s*|\s+|(?=[.?!,])|$)"#,
        #"(?i)(^|[\s,])(basically|literally|i mean|actually)(,\s*|\s+|(?=[.?!,])|$)"#,
        #"(?i)(^|[\s,])(like)(,\s*|\s+)(?=(?:really|very|just|so|super|totally|literally|basically|actually|kind of|sort of|a bit|a lot|pretty|quite)\b)"#,
        // "kind of" and "sort of" hedge an adjective; before a noun they are the phrase.
        #"(?i)(^|[\s,])(kind of|sort of)(\s+)(?!(?:a|an|the|this|that|these|those|my|your|our|their|thing|things|person|people|stuff|way|place|error|problem|issue|work|job|guy|idea|deal|situation)\b)(?=[a-z])"#,
        #"(?i)(^|[.?!]\s+)(like)(,\s*|\s+)(?=(?:i|you|we|they|he|she|it|there|this|that|the|my|your|our)\b)"#,
    ].map { try! NSRegularExpression(pattern: $0) }

    static func cutFillers(_ text: String) -> String {
        var t = asidePattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        for p in fillerPatterns {
            t = p.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "$1")
        }
        t = t.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+([.?!,])"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #",\s*,"#, with: ",", options: .regularExpression)
        t = t.replacingOccurrences(of: #"^[\s,]+"#, with: "", options: .regularExpression)
        return capitaliseSentences(t.trimmingCharacters(in: .whitespaces))
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
    /// The same counters anywhere, for a transcript clean-up left unpunctuated.
    private static let looseMarkerPattern = try! NSRegularExpression(
        pattern: #"(?i)(?:^|(?<=\s))(?<!\b(?:the|a|my|your|his|her|our|their|this|that|came|come|finished|at|in|for)\s)(?:(?:and|then)\s+)?(first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth)(?:ly)?[,:.]?\s+"#)
    private static let fillerSounds = try! NSRegularExpression(pattern: #"(?i)(^|\s)(?:um+|uh+|er+|ah+)(?=\s|$)"#)

    /// "Three things. First, a. Second, b. And third, c." becomes the lead-in
    /// on one line and a numbered item per line. Needs at least two counters,
    /// in order from first; anything else is left as prose. Counters are
    /// looked for at sentence starts, and anywhere when that finds too few,
    /// since clean-up sometimes returns the transcript without punctuation.
    /// The counters of a spoken list, in order from first, or none.
    static func counters(in text: String) -> [NSTextCheckingResult] {
        let ns = text as NSString
        var found = markerPattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
        if found.count < 2 { found = looseMarkerPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) }
        guard found.count >= 2 else { return [] }
        for (n, m) in found.enumerated() where ns.substring(with: m.range(at: 1)).lowercased() != markers[n] { return [] }
        return found
    }

    static func numberedList(_ text: String) -> String {
        let ns = text as NSString
        let found = counters(in: text)
        guard !found.isEmpty else { return text }
        var lines: [String] = []
        let lead = ns.substring(to: found[0].range.location).trimmingCharacters(in: .whitespacesAndNewlines)
        if !lead.isEmpty { lines.append(capitaliseSentences(lead)) }
        for (n, m) in found.enumerated() {
            let start = m.range.location + m.range.length
            let end = n + 1 < found.count ? found[n + 1].range.location : ns.length
            var item = ns.substring(with: NSRange(location: start, length: end - start))
            item = fillerSounds.stringByReplacingMatches(in: item, range: NSRange(item.startIndex..., in: item), withTemplate: "$1")
            item = item.trimmingCharacters(in: .whitespacesAndNewlines)
            while let last = item.last, ",;".contains(last) { item.removeLast() }
            item = item.trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append("\(n + 1). " + capitaliseSentences(item))
        }
        // Items end alike: all with a full stop when any does.
        if lines.contains(where: { $0.hasSuffix(".") }) {
            lines = lines.map { $0.last.map { ".?!:".contains($0) } == true ? $0 : $0 + "." }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Contractions

    /// The contractions that are never wrong. A subject and verb are joined
    /// only when a word follows, so "that is what it is" and "here I am" keep
    /// their last word, and not after where or how ("where we are with it");
    /// "has" is joined only before a past participle ("she has finished",
    /// never "she has a car"); "let us" is never joined ("let us know").
    private static let negatives: [(String, String)] = [
        ("cannot", "can't"), ("can not", "can't"), ("will not", "won't"), ("shall not", "shan't"),
        ("do not", "don't"), ("does not", "doesn't"), ("did not", "didn't"), ("could not", "couldn't"),
        ("would not", "wouldn't"), ("should not", "shouldn't"), ("is not", "isn't"), ("are not", "aren't"),
        ("was not", "wasn't"), ("were not", "weren't"), ("has not", "hasn't"), ("have not", "haven't"),
        ("had not", "hadn't"), ("must not", "mustn't"), ("would have", "would've"), ("could have", "could've"),
        ("should have", "should've"),
    ]
    private static let joins: [(String, String)] = [
        ("i am", "I'm"), ("i have", "I've"), ("i will", "I'll"), ("i would", "I'd"),
        ("you are", "you're"), ("you have", "you've"), ("you will", "you'll"), ("you would", "you'd"),
        ("we are", "we're"), ("we have", "we've"), ("we will", "we'll"), ("we would", "we'd"),
        ("they are", "they're"), ("they have", "they've"), ("they will", "they'll"), ("they would", "they'd"),
        ("he is", "he's"), ("he will", "he'll"), ("he would", "he'd"),
        ("she is", "she's"), ("she will", "she'll"), ("she would", "she'd"),
        ("it is", "it's"), ("it will", "it'll"), ("that is", "that's"), ("that will", "that'll"),
        ("there is", "there's"), ("there will", "there'll"), ("here is", "here's"),
        ("what is", "what's"), ("who is", "who's"), ("where is", "where's"), ("how is", "how's"),
    ]
    /// "has" joins only before a past participle: "she has finished" → she's finished, "she has a car" stays.
    private static let hasSubjects = ["he", "she", "it", "who", "that", "there", "nobody", "everybody", "someone", "everyone"]
    private static let irregularParticiples = "been|gone|done|seen|got|gotten|had|made|taken|given|come|become|left|lost|won|said|told|found|run|put|set|brought|thought|bought|sent|built|kept|felt|met|paid|read|written|spoken|broken|chosen|forgotten|eaten|fallen|driven|flown|known|shown|grown|thrown|drawn|worn|torn|begun|sung|drunk|caught|taught|fought|heard|held|led|sold|stood|understood|cut|hit|let|quit|shut|spent|sat|slept|woken|beaten|hidden|ridden|risen|shaken|stolen|struck|swept|sworn|blown|frozen|bitten|lain|meant|sought|won"

    /// Subjects join before "is not" and "are not" are looked at, so "it is
    /// not" reads it's not rather than it isn't; "will not" still wins over
    /// we'll not because it goes first.
    static func contract(_ text: String) -> String {
        var t = text
        let late = ["is not", "are not", "am not"]
        for (long, short) in negatives where !late.contains(long) {
            t = replaceWords(long, with: short, in: t, needsFollowingWord: false)
        }
        for (long, short) in joins {
            t = replaceWords(long, with: short, in: t, needsFollowingWord: true)
        }
        for (long, short) in negatives where late.contains(long) {
            t = replaceWords(long, with: short, in: t, needsFollowingWord: false)
        }
        for subject in hasSubjects {
            let re = try! NSRegularExpression(pattern: #"(?i)\b("# + subject + #")\s+has(?=\s+(?:\w+ed|"# + irregularParticiples + #")\b)"#)
            t = re.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "$1's")
        }
        return t
    }

    /// Replaces a phrase as whole words, keeping the case of its first letter.
    private static func replaceWords(_ long: String, with short: String, in text: String, needsFollowingWord: Bool) -> String {
        let phrase = NSRegularExpression.escapedPattern(for: long).replacingOccurrences(of: " ", with: "\\s+")
        let tail = needsFollowingWord ? #"(?=\s+[a-z])"# : #"\b"#
        let head = needsFollowingWord ? #"(?<!\bwhere\s)(?<!\bhow\s)"# : ""
        let re = try! NSRegularExpression(pattern: #"(?i)"# + head + #"\b"# + phrase + tail)
        let ns = text as NSString
        var out = text
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let original = ns.substring(with: m.range)
            var replacement = short
            if let f = original.first, f.isUppercase, short.first?.isLowercase == true {
                replacement = short.prefix(1).uppercased() + short.dropFirst()
            }
            out = (out as NSString).replacingCharacters(in: m.range, with: replacement)
        }
        return out
    }

    // MARK: Quotes

    /// The words after a reporting verb, up to the end of the sentence or
    /// the next clause with its own subject, are what was said: she said
    /// ship it → she said "ship it". "that" after the verb is indirect
    /// speech and stays as it is. Straight quotes, no comma, no capital.
    private static let reportPattern = try! NSRegularExpression(pattern:
        #"(?i)\b(said|says|saying|told (?:me|him|her|us|them|everyone)|asked(?: (?:me|him|her|us|them))?|replied|shouted|whispered|texted|wrote|goes|(?:was|were|is|are|am|I'm|he's|she's|they're|we're) like)(,?\s+)(?!that\b|if\b|whether\b|to\b|about\b|nothing\b|something\b|anything\b|so\b|it\b|this\b)([^"\n]+?)(?=[.?!;:]|\s*$|,?\s+(?:and|but|so|then|because)\s+(?:i|he|she|they|we|it|you|that|this|there|[A-Z][a-z]+)\b)"#)

    static func quote(_ text: String) -> String {
        var out = text
        for m in reportPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            let ns = out as NSString
            let said = ns.substring(with: m.range(at: 3)).trimmingCharacters(in: .whitespaces)
            guard !said.isEmpty else { continue }
            let replacement = ns.substring(with: m.range(at: 1)) + ns.substring(with: m.range(at: 2)) + "\"" + said + "\""
            out = ns.replacingCharacters(in: m.range, with: replacement)
        }
        return out
    }

    // MARK: Digits

    static func digits(_ text: String) -> String { Digits.apply(text) }
}
