import Foundation

/// Transcript cleanup: custom-word correction, filler-word removal and
/// whitespace/stutter normalisation.
///
/// Port of TypeMeIt's `audio_toolkit/text.rs`, plus `is_blank_transcription` and
/// `strip_think_block` from `actions.rs`. Everything here is a pure function;
/// the enum is a namespace only.
///
/// Rust `char` semantics are preserved by working on Unicode scalars, not
/// Swift `Character`s: classification (`is_alphanumeric`, `is_whitespace`,
/// `is_uppercase`) and case mapping are per scalar, and string equality is
/// scalar-wise rather than canonical equivalence.
enum TextCleanup {
    /// A learned mishearing: `heard` is a form the speech model has produced
    /// for `meant` before.
    struct Alias: Sendable, Equatable {
        var heard: String
        var meant: String
    }

    struct Result: Sendable, Equatable {
        var text: String
        /// Number of custom-word substitutions that changed the text.
        var dictionaryFixes: Int
    }

    /// Full pipeline in TypeMeIt's order: custom words (with aliases) -> filler removal -> normalisation.
    static func run(
        _ text: String,
        customWords: [String],
        aliases: [Alias],
        threshold: Double = 0.18
    ) -> Result {
        let corrected = applyCustomWords(
            text, customWords: customWords, aliases: aliases, threshold: threshold
        )
        let filtered = removeFillerWords(corrected.text)
        return Result(text: normalize(filtered), dictionaryFixes: corrected.fixes)
    }

    // MARK: - Custom words

    private struct CustomWordMatchKey {
        var wordIndex: Int
        var key: String
    }

    /// Builds an n-gram string by cleaning and concatenating words.
    ///
    /// Strips punctuation from each word, lowercases, and joins without spaces.
    /// This allows matching "Charge B" against "ChargeBee".
    private static func buildNgram(_ words: ArraySlice<String>) -> String {
        words.map(buildMatchKey).joined()
    }

    private static func buildMatchKey(_ word: String) -> String {
        var key = String.UnicodeScalarView()
        for c in word.unicodeScalars where isAlphanumeric(c) {
            key.append(contentsOf: c.properties.lowercaseMapping.unicodeScalars)
        }
        return String(key)
    }

    private static func buildCustomWordMatchKeys(_ word: String, wordIndex: Int) -> [CustomWordMatchKey] {
        let primaryKey = buildMatchKey(word)
        var keys: [CustomWordMatchKey] = []
        keys.reserveCapacity(2)

        // The fallback matcher is intentionally limited to ASCII terms. Its
        // whitespace tokenization and Soundex scoring are not suitable for CJK
        // scripts. Unicode custom words remain available to models that accept
        // them as native decode prompts; they are simply skipped by this fallback.
        if isSupportedFuzzyKey(primaryKey) {
            keys.append(CustomWordMatchKey(wordIndex: wordIndex, key: primaryKey))
        }

        if word.unicodeScalars.contains("&") {
            let expandedKey = buildMatchKey(replacingScalar("&", with: " and ", in: word))
            if isSupportedFuzzyKey(expandedKey) && !scalarsEqual(expandedKey, primaryKey) {
                keys.append(CustomWordMatchKey(wordIndex: wordIndex, key: expandedKey))
            }
        }

        return keys
    }

    private static func isSupportedFuzzyKey(_ key: String) -> Bool {
        !key.isEmpty && key.unicodeScalars.allSatisfy(isASCIIAlphanumeric)
    }

    private static func supportsSoundex(_ key: String) -> Bool {
        !key.isEmpty && key.unicodeScalars.allSatisfy(isASCIIAlphabetic)
    }

    /// Finds the best matching custom word for a candidate string.
    ///
    /// Uses Levenshtein distance and Soundex phonetic matching to find
    /// the best match below the given threshold.
    ///
    /// - Parameters:
    ///   - candidate: The cleaned/lowercased candidate string to match.
    ///   - customWords: Original custom words (for returning the replacement).
    ///   - customWordMatchKeys: Normalized custom-word keys for comparison.
    ///   - threshold: Maximum similarity score to accept.
    /// - Returns: The best matching custom word and its score, if any match was found.
    private static func findBestMatch(
        _ candidate: String,
        customWords: [String],
        customWordMatchKeys: [CustomWordMatchKey],
        threshold: Double
    ) -> (replacement: String, score: Double)? {
        let candidateLen = candidate.unicodeScalars.count
        if !isSupportedFuzzyKey(candidate) || candidateLen > 50 {
            return nil
        }

        var bestMatch: String? = nil
        var bestScore = Double.greatestFiniteMagnitude

        for customWordKey in customWordMatchKeys {
            // Skip if lengths are too different (optimization + prevents over-matching)
            // Use percentage-based check: max 25% length difference (prevents n-grams from
            // matching significantly shorter custom words, e.g., "openaigpt" vs "openai")
            let customWordLen = customWordKey.key.unicodeScalars.count
            let lenDiff = Double(abs(candidateLen - customWordLen))
            let maxLen = Double(max(candidateLen, customWordLen))
            let maxAllowedDiff = max(maxLen * 0.25, 2.0) // At least 2 chars difference allowed
            if lenDiff > maxAllowedDiff {
                continue
            }

            // Calculate Levenshtein distance (normalized by length)
            let levenshteinDist = levenshtein(candidate, customWordKey.key)
            let levenshteinScore = maxLen > 0.0 ? Double(levenshteinDist) / maxLen : 1.0

            // Soundex is an English/ASCII phonetic algorithm. Numeric terms can
            // still use edit distance, but must not receive a phonetic boost.
            let phoneticMatch = supportsSoundex(candidate)
                && supportsSoundex(customWordKey.key)
                && soundex(candidate, customWordKey.key)

            // Combine scores: favor phonetic matches, but also consider string similarity
            let combinedScore = phoneticMatch
                ? levenshteinScore * 0.3 // Give significant boost to phonetic matches
                : levenshteinScore

            // Accept if the score is good enough (configurable threshold)
            if combinedScore < threshold && combinedScore < bestScore {
                bestMatch = customWords[customWordKey.wordIndex]
                bestScore = combinedScore
            }
        }

        return bestMatch.map { ($0, bestScore) }
    }

    /// Applies custom word corrections to transcribed text using fuzzy matching.
    ///
    /// Corrects words in the input text by finding the best matches from a
    /// list of custom words using a combination of:
    /// - Levenshtein distance for string similarity
    /// - Soundex phonetic matching for pronunciation similarity
    /// - N-gram matching for multi-word speech artifacts (e.g., "Charge B" -> "ChargeBee")
    ///
    /// Each alias is a form the speech model has produced for a custom word
    /// before. It matches like the custom word itself, so a transcript close to
    /// a past mishearing is corrected even when it is far from the right
    /// spelling. Aliases whose `meant` is not a custom word are ignored.
    ///
    /// - Parameters:
    ///   - text: The input text to correct.
    ///   - customWords: List of custom words to match against.
    ///   - aliases: Extra spellings to match against.
    ///   - threshold: Maximum similarity score to accept (0.0 = exact match, 1.0 = any match).
    /// - Returns: The corrected text and the number of substitutions that changed it.
    static func applyCustomWords(
        _ text: String,
        customWords: [String],
        aliases: [Alias],
        threshold: Double
    ) -> (text: String, fixes: Int) {
        if customWords.isEmpty {
            return (text, 0)
        }

        // Pre-compute normalized comparison keys to avoid repeated allocations.
        var customWordMatchKeys: [CustomWordMatchKey] = customWords.enumerated().flatMap {
            buildCustomWordMatchKeys($0.element, wordIndex: $0.offset)
        }
        for alias in aliases {
            let meantKey = buildMatchKey(alias.meant)
            guard let wordIndex = customWords.firstIndex(where: {
                scalarsEqual(buildMatchKey($0), meantKey)
            }) else {
                continue
            }
            let key = buildMatchKey(alias.heard)
            if isSupportedFuzzyKey(key)
                && !customWordMatchKeys.contains(where: {
                    $0.wordIndex == wordIndex && scalarsEqual($0.key, key)
                })
            {
                customWordMatchKeys.append(CustomWordMatchKey(wordIndex: wordIndex, key: key))
            }
        }

        let words = splitWhitespace(text)
        var result: [String] = []
        var fixes = 0
        var i = 0

        while i < words.count {
            var bestMatch: (n: Int, replacement: String, score: Double)? = nil

            // Consider n-grams up to three words and choose the closest match. A
            // longest-first match can consume a following ordinary word when both
            // candidates happen to share a Soundex code (for example,
            // "Charge B, che" matching "ChargeBee").
            for n in stride(from: 3, through: 1, by: -1) {
                if i + n > words.count {
                    continue
                }

                let ngramWords = words[i..<(i + n)]
                // Do not consume across a punctuation boundary. In
                // "Charge B, che", the comma closes the candidate at "B,".
                if ngramWords.prefix(n - 1).contains(where: { !extractPunctuation($0).suffix.isEmpty }) {
                    continue
                }
                let ngram = buildNgram(ngramWords)

                if let match = findBestMatch(
                    ngram,
                    customWords: customWords,
                    customWordMatchKeys: customWordMatchKeys,
                    threshold: threshold
                ) {
                    let isBetter = bestMatch.map { match.score < $0.score } ?? true
                    if isBetter {
                        bestMatch = (n, match.replacement, match.score)
                    }
                }
            }

            if let best = bestMatch {
                let n = best.n
                let ngramWords = words[i..<(i + n)]
                // Extract punctuation from first and last words of the n-gram.
                let prefix = extractPunctuation(words[i]).prefix
                let suffix = extractPunctuation(words[i + n - 1]).suffix

                // Preserve case from first word.
                let corrected = preserveCasePattern(words[i], best.replacement)

                let token = prefix + corrected + suffix
                if !scalarsEqual(token, ngramWords.joined(separator: " ")) {
                    fixes += 1
                }
                result.append(token)
                i += n
            } else {
                result.append(words[i])
                i += 1
            }
        }

        return (result.joined(separator: " "), fixes)
    }

    /// Preserves the case pattern of the original word when applying a replacement.
    /// Internal for tests.
    static func preserveCasePattern(_ original: String, _ replacement: String) -> String {
        if original.unicodeScalars.allSatisfy({ $0.properties.isUppercase }) {
            return replacement.uppercased()
        } else if let first = original.unicodeScalars.first, first.properties.isUppercase {
            var chars = Array(replacement.unicodeScalars)
            if !chars.isEmpty {
                chars[0] = chars[0].properties.uppercaseMapping.unicodeScalars.first ?? chars[0]
            }
            return string(chars)
        } else {
            return replacement
        }
    }

    /// Extracts punctuation prefix and suffix from a word.
    /// Internal for tests.
    static func extractPunctuation(_ word: String) -> (prefix: String, suffix: String) {
        // Boundaries are scalar offsets, so multibyte punctuation such as `。`
        // and `「」` can never be split.
        let scalars = Array(word.unicodeScalars)
        let prefixEnd = scalars.firstIndex(where: isAlphanumeric) ?? scalars.count
        let suffixStart = scalars.lastIndex(where: isAlphanumeric).map { $0 + 1 } ?? 0

        let prefix = prefixEnd > 0 ? string(scalars[..<prefixEnd]) : ""
        let suffix = suffixStart < scalars.count ? string(scalars[suffixStart...]) : ""

        return (prefix, suffix)
    }

    // MARK: - Filler words

    /// Filler tokens that are not lexical words in any language TypeMeIt's models can
    /// output, so removing them cannot corrupt text regardless of the output
    /// language. Kept deliberately conservative: anything that is a real word
    /// somewhere ("um" pt/de, "ha" es, "ah"/"eh" interjections, "mm" millimetres)
    /// belongs in the English-gated list instead.
    static let universalFillerWords: [String] = [
        "uh", "uhm", "umm", "uhh", "uhhh", "ehh", "ehm", "ahm", "hmm", "hm", "mmm", "хм", "ммм",
    ]

    /// Filler words that are only safe to remove because the app is
    /// English-only: the same token is a real word elsewhere (e.g. Portuguese
    /// "um" = "a/an", German "um" = "at/around", Spanish "ha" = "has").
    static let englishFillerWords: [String] = ["um", "ah", "eh", "ha"]

    /// One `(?i)\bWORD\b[,.]?` pattern per filler word, in list order.
    private static let fillerPatterns: [NSRegularExpression] =
        (universalFillerWords + englishFillerWords).map { word in
            // Constant patterns; a failure here is a programming error, as in the Rust `unwrap`.
            // swiftlint:disable:next force_try
            try! NSRegularExpression(
                pattern: "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b[,.]?",
                options: [.caseInsensitive]
            )
        }

    /// Removes filler words from transcription output.
    ///
    /// The word list is the union of `universalFillerWords` and
    /// `englishFillerWords`. Each pattern is applied in turn, deleting the word
    /// and one directly following `,` or `.`.
    static func removeFillerWords(_ text: String) -> String {
        var filtered = text
        for pattern in fillerPatterns {
            filtered = pattern.stringByReplacingMatches(
                in: filtered,
                range: NSRange(filtered.startIndex..., in: filtered),
                withTemplate: ""
            )
        }
        return filtered
    }

    // MARK: - Normalisation

    /// Collapses repeated words (3+ repetitions) to a single instance.
    /// E.g., "wh wh wh wh" -> "wh", "I I I I" -> "I"
    private static func collapseStutters(_ text: String) -> String {
        let words = splitWhitespace(text)
        if words.isEmpty {
            return text
        }

        var result: [String] = []
        var i = 0

        while i < words.count {
            let word = words[i]
            let wordLower = word.lowercased()

            if wordLower.unicodeScalars.allSatisfy({ $0.properties.isAlphabetic }) {
                // Count consecutive repetitions (case-insensitive)
                var count = 1
                while i + count < words.count && scalarsEqual(words[i + count].lowercased(), wordLower) {
                    count += 1
                }

                // If 3+ repetitions, collapse to single instance
                if count >= 3 {
                    result.append(word)
                    i += count
                } else {
                    result.append(word)
                    i += 1
                }
            } else {
                result.append(word)
                i += 1
            }
        }

        return result.joined(separator: " ")
    }

    /// Applies non-filler transcription cleanup: stutter collapse, runs of two
    /// or more whitespace scalars become one space, then leading and trailing
    /// whitespace is trimmed.
    ///
    /// Kept separate from `removeFillerWords` so disabling filler deletion
    /// does not also disable the repeated-word and whitespace cleanup.
    static func normalize(_ text: String) -> String {
        var normalized = collapseStutters(text)

        // Clean up multiple spaces to single space (`\s{2,}` -> " ")
        normalized = collapseWhitespaceRuns(normalized)

        // Trim leading/trailing whitespace
        return trim(normalized)
    }

    private static func collapseWhitespaceRuns(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        var run: [Unicode.Scalar] = []
        func flush() {
            if run.count >= 2 {
                out.append(" ")
            } else {
                out.append(contentsOf: run)
            }
            run.removeAll(keepingCapacity: true)
        }
        for c in text.unicodeScalars {
            if isWhitespace(c) {
                run.append(c)
            } else {
                flush()
                out.append(c)
            }
        }
        flush()
        return String(out)
    }

    private static func trim(_ text: String) -> String {
        let scalars = text.unicodeScalars
        let trimmed = scalars.drop(while: isWhitespace)
        guard let lastNonWhitespace = trimmed.lastIndex(where: { !isWhitespace($0) }) else {
            return ""
        }
        return String(trimmed[...lastNonWhitespace])
    }

    // MARK: - Post-processing helpers (actions.rs)

    /// `true` when a transcription has no meaningful content to post-process
    /// (empty or whitespace-only). Used to skip the post-processing LLM call
    /// when nothing was transcribed, which would otherwise make the model
    /// reply with an error message such as "you need to provide the
    /// transcription".
    static func isBlank(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy(isWhitespace)
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

    // MARK: - Distance metrics

    /// Standard Levenshtein edit distance over Unicode scalars (strsim semantics).
    /// Internal for tests.
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

    /// `true` when both words have the same Soundex code.
    /// Internal for tests.
    static func soundex(_ word1: String, _ word2: String) -> Bool {
        soundexEncoding(word1) == soundexEncoding(word2)
    }

    /// Soundex code as implemented by the `natural` crate (4 characters).
    ///
    /// Differs from textbook American Soundex in that the first letter is kept
    /// verbatim and is never merged with a following consonant of the same
    /// class. Callers pass lowercase ASCII letters only; other input maps to
    /// the vowel class. An empty word encodes as `0000`.
    /// Internal for tests.
    static func soundexEncoding(_ word: String) -> String {
        string(fixLength(stripSimilarChars(Array(word.unicodeScalars))))
    }

    private static func stripSimilarChars(_ chars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        guard let first = chars.first else {
            return []
        }
        var encChars: [Unicode.Scalar] = [first]
        for c in chars.dropFirst() {
            encChars.append(soundexDigit(c))
        }
        var charsNoHW: [Unicode.Scalar] = []
        for c in encChars where c != "9" {
            // dedup: drop consecutive repeats
            if charsNoHW.last != c {
                charsNoHW.append(c)
            }
        }
        return charsNoHW.filter { $0 != "0" }
    }

    private static func fixLength(_ chars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        switch chars.count {
        case 4:
            return chars
        case 0...3:
            return (0..<4).map { idx in idx < chars.count ? chars[idx] : "0" }
        default:
            return Array(chars.prefix(4))
        }
    }

    private static func soundexDigit(_ c: Unicode.Scalar) -> Unicode.Scalar {
        switch c {
        case "b", "f", "p", "v": return "1"
        case "c", "g", "j", "k", "q", "s", "x", "z": return "2"
        case "d", "t": return "3"
        case "l": return "4"
        case "m", "n": return "5"
        case "r": return "6"
        case "h", "w": return "9" // 0 and 9 are removed later, this is just to separate vowels from h and w
        default: return "0" // Vowels
        }
    }

    // MARK: - Scalar helpers (Rust `char` semantics)

    /// Rust `char::is_alphanumeric`: Alphabetic, or general category Nd/Nl/No.
    private static func isAlphanumeric(_ c: Unicode.Scalar) -> Bool {
        let properties = c.properties
        if properties.isAlphabetic {
            return true
        }
        switch properties.generalCategory {
        case .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }

    /// Rust `char::is_whitespace`: the White_Space property.
    private static func isWhitespace(_ c: Unicode.Scalar) -> Bool {
        c.properties.isWhitespace
    }

    private static func isASCIIAlphabetic(_ c: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(c) || ("A"..."Z").contains(c)
    }

    private static func isASCIIAlphanumeric(_ c: Unicode.Scalar) -> Bool {
        isASCIIAlphabetic(c) || ("0"..."9").contains(c)
    }

    /// Rust `str::split_whitespace`.
    private static func splitWhitespace(_ text: String) -> [String] {
        text.unicodeScalars.split(whereSeparator: isWhitespace).map { String($0) }
    }

    /// Rust `str::replace(char, &str)`.
    private static func replacingScalar(_ target: Unicode.Scalar, with replacement: String, in text: String) -> String {
        var out = String.UnicodeScalarView()
        for c in text.unicodeScalars {
            if c == target {
                out.append(contentsOf: replacement.unicodeScalars)
            } else {
                out.append(c)
            }
        }
        return String(out)
    }

    /// Rust `String ==`: byte equality, not canonical equivalence.
    private static func scalarsEqual(_ a: String, _ b: String) -> Bool {
        a.unicodeScalars.elementsEqual(b.unicodeScalars)
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
