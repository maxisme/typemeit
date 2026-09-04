import XCTest
@testable import TypeMeIt

final class TextCleanupTests: XCTestCase {
    /// Exercise the complete cleanup sequence minus custom words, mirroring
    /// the Rust test helper `filter_transcription_output`.
    private func filterTranscriptionOutput(_ text: String) -> String {
        TextCleanup.normalize(TextCleanup.removeFillerWords(text))
    }

    private func applyCustomWords(_ text: String, _ customWords: [String], _ threshold: Double) -> String {
        TextCleanup.applyCustomWords(text, customWords: customWords, aliases: [], threshold: threshold).text
    }

    // MARK: - Aliases

    func testAliasesMatchFormsCloseToAPastMishearing() {
        let customWords = ["Zentryx"]
        let aliases = [TextCleanup.Alias(heard: "Zentrix", meant: "Zentryx")]
        XCTAssertEqual(
            applyCustomWords("Centrix is the cluster", customWords, 0.18),
            "Centrix is the cluster"
        )
        XCTAssertEqual(
            TextCleanup.applyCustomWords(
                "Centrix is the cluster", customWords: customWords, aliases: aliases, threshold: 0.18
            ).text,
            "Zentryx is the cluster"
        )
    }

    func testAliasesForWordsNotInTheListAreIgnored() {
        let customWords = ["Kavuu"]
        let aliases = [TextCleanup.Alias(heard: "Zentrix", meant: "Zentryx")]
        XCTAssertEqual(
            TextCleanup.applyCustomWords(
                "Zentrix is here", customWords: customWords, aliases: aliases, threshold: 0.18
            ).text,
            "Zentrix is here"
        )
    }

    // MARK: - Custom words

    func testApplyCustomWordsExactMatch() {
        XCTAssertEqual(applyCustomWords("hello world", ["Hello", "World"], 0.5), "Hello World")
    }

    func testApplyCustomWordsFuzzyMatch() {
        XCTAssertEqual(applyCustomWords("helo wrold", ["hello", "world"], 0.5), "hello world")
    }

    func testPreserveCasePattern() {
        XCTAssertEqual(TextCleanup.preserveCasePattern("HELLO", "world"), "WORLD")
        XCTAssertEqual(TextCleanup.preserveCasePattern("Hello", "world"), "World")
        XCTAssertEqual(TextCleanup.preserveCasePattern("hello", "WORLD"), "WORLD")
    }

    private func assertPunctuation(
        _ word: String, prefix: String, suffix: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let extracted = TextCleanup.extractPunctuation(word)
        XCTAssertEqual(extracted.prefix, prefix, file: file, line: line)
        XCTAssertEqual(extracted.suffix, suffix, file: file, line: line)
    }

    func testExtractPunctuation() {
        assertPunctuation("hello", prefix: "", suffix: "")
        assertPunctuation("!hello?", prefix: "!", suffix: "?")
        assertPunctuation("...hello...", prefix: "...", suffix: "...")
    }

    func testExtractPunctuationUsesUnicodeBoundaries() {
        assertPunctuation("你好。", prefix: "", suffix: "。")
        assertPunctuation("「你好」", prefix: "「", suffix: "」")
        assertPunctuation("你好！", prefix: "", suffix: "！")
    }

    func testEmptyCustomWords() {
        XCTAssertEqual(applyCustomWords("hello world", [], 0.5), "hello world")
    }

    func testApplyCustomWordsNgramTwoWords() {
        let result = applyCustomWords("il cui nome è Charge B, che permette", ["ChargeBee"], 0.5)
        XCTAssertEqual(result, "il cui nome è ChargeBee, che permette")
    }

    func testApplyCustomWordsNgramThreeWords() {
        let result = applyCustomWords("use Chat G P T for this", ["ChatGPT"], 0.5)
        XCTAssertEqual(result, "use ChatGPT T for this")
    }

    func testApplyCustomWordsPrefersLongerNgram() {
        let result = applyCustomWords("Open AI GPT model", ["OpenAI", "GPT"], 0.5)
        XCTAssertEqual(result, "OpenAI GPT model")
    }

    func testApplyCustomWordsNgramPreservesCase() {
        // "chargebis" (3-gram) and "chargeb" (2-gram) score identically; the
        // 3-gram is considered first and a later candidate must be strictly
        // better, so "is" is consumed. Same as the Rust.
        let result = applyCustomWords("CHARGE B is great", ["ChargeBee"], 0.5)
        XCTAssertEqual(result, "CHARGEBEE great")
    }

    func testApplyCustomWordsNgramWithSpacesInCustom() {
        // Custom word with space should also match against split words
        let result = applyCustomWords("using Mac Book Pro", ["MacBook Pro"], 0.5)
        XCTAssertEqual(result, "using MacBook Pro")
    }

    func testApplyCustomWordsTrailingNumberNotDoubled() {
        // Trailing non-alpha chars (like numbers) must not be double-counted
        // between buildNgram stripping them and extractPunctuation capturing them.
        let result = applyCustomWords("use GPT4 for this", ["GPT-4"], 0.5)
        XCTAssertEqual(result, "use GPT-4 for this")
    }

    func testApplyCustomWordsMatchesAmpersandWord() {
        XCTAssertEqual(
            applyCustomWords("send it to RD for review", ["R&D"], 0.18),
            "send it to R&D for review"
        )
    }

    func testApplyCustomWordsMatchesSpokenAmpersandWord() {
        XCTAssertEqual(
            applyCustomWords("send it to R and D for review", ["R&D"], 0.18),
            "send it to R&D for review"
        )
    }

    func testApplyCustomWordsPreservesAmpersandWord() {
        XCTAssertEqual(
            applyCustomWords("send it to R&D for review", ["R&D"], 0.18),
            "send it to R&D for review"
        )
    }

    func testApplyCustomWordsHandlesUnicodePunctuation() {
        XCTAssertEqual(applyCustomWords("「Handee。」", ["Handy"], 0.5), "「Handy。」")
    }

    func testApplyCustomWordsSkipsCJKFuzzyMatching() {
        let text = "你好。"
        XCTAssertEqual(applyCustomWords(text, ["你号"], 1.0), text)
    }

    // MARK: - Filler words

    func testFilterFillerWords() {
        XCTAssertEqual(
            filterTranscriptionOutput("So uhm I was thinking uh about this"),
            "So I was thinking about this"
        )
    }

    func testFilterFillerWordsCaseInsensitive() {
        XCTAssertEqual(filterTranscriptionOutput("UHM this is UH a test"), "this is a test")
    }

    func testFilterFillerWordsWithPunctuation() {
        XCTAssertEqual(
            filterTranscriptionOutput("Well, uhm, I think, uh. that's right"),
            "Well, I think, that's right"
        )
    }

    func testFillerRemovalLeavesWhitespaceForNormalize() {
        XCTAssertEqual(
            TextCleanup.removeFillerWords("Well, uhm, I think, uh. that's right"),
            "Well,  I think,  that's right"
        )
    }

    func testFillerRemovalRespectsWordBoundaries() {
        // "ham", "hum", "uhmm", "humm" contain fillers but are not fillers.
        // Only one directly following "," or "." is consumed, not "?" or "!".
        XCTAssertEqual(
            TextCleanup.removeFillerWords("ham hum uhmm humm eh? Uh!"),
            "ham hum uhmm humm ? !"
        )
    }

    func testFillerOnlyTextBecomesEmpty() {
        XCTAssertEqual(filterTranscriptionOutput("um, uh. ah, eh. ha, hmm."), "")
    }

    func testFilterCleansWhitespace() {
        XCTAssertEqual(filterTranscriptionOutput("Hello    world   test"), "Hello world test")
    }

    func testFilterTrims() {
        XCTAssertEqual(filterTranscriptionOutput("  Hello world  "), "Hello world")
    }

    func testFilterCombined() {
        XCTAssertEqual(
            filterTranscriptionOutput("  Uhm, so I was, uh, thinking about this  "),
            "so I was, thinking about this"
        )
    }

    func testFilterPreservesValidText() {
        XCTAssertEqual(
            filterTranscriptionOutput("This is a completely normal sentence."),
            "This is a completely normal sentence."
        )
    }

    func testFilterEnglishRemovesUm() {
        XCTAssertEqual(
            filterTranscriptionOutput("um I think um this is good"),
            "I think this is good"
        )
    }

    func testFilterRemovesUniversalFillers() {
        XCTAssertEqual(filterTranscriptionOutput("uh I think uhm this works"), "I think this works")
    }

    func testFilterRemovesCyrillicUniversalFillers() {
        XCTAssertEqual(
            filterTranscriptionOutput("хм я думаю ммм это работает"),
            "я думаю это работает"
        )
    }

    func testFilterIsEnglishOnly() {
        // The Rust gates "um"/"ha" on language evidence because they are real
        // words in Portuguese and Spanish. This port is English-only, so they
        // are always removed.
        XCTAssertEqual(filterTranscriptionOutput("um gato bonito"), "gato bonito")
        XCTAssertEqual(filterTranscriptionOutput("ha sido un buen día"), "sido un buen día")
    }

    func testGermanAndFrenchFillersAreNotRemoved() {
        // "äh"/"ähm"/"euh" are in the Rust's de/fr gated lists, not the English one.
        let german = "äh ich glaube ähm das passt"
        XCTAssertEqual(filterTranscriptionOutput(german), german)
        let french = "euh je pense que ça marche"
        XCTAssertEqual(filterTranscriptionOutput(french), french)
    }

    func testFilterPreservesMillimetreUnit() {
        // "mm" is not in the filler lists because it eats units.
        XCTAssertEqual(filterTranscriptionOutput("the screw is 5 mm long"), "the screw is 5 mm long")
    }

    // MARK: - Stutters and whitespace

    func testFilterStutterCollapse() {
        XCTAssertEqual(filterTranscriptionOutput("w wh wh wh wh wh wh wh wh wh why"), "w wh why")
    }

    func testFilterStutterShortWords() {
        XCTAssertEqual(filterTranscriptionOutput("I I I I think so so so so"), "I think so")
    }

    func testFilterStutterLongerWords() {
        XCTAssertEqual(
            filterTranscriptionOutput("Check data doc doc doc doc documentation."),
            "Check data doc documentation."
        )
    }

    func testFilterStutterMixedCase() {
        XCTAssertEqual(filterTranscriptionOutput("No NO no NO no"), "No")
    }

    func testFilterStutterPreservesTwoRepetitions() {
        XCTAssertEqual(filterTranscriptionOutput("no no is fine"), "no no is fine")
    }

    func testNormalizeTreatsAllUnicodeWhitespaceAsSeparators() {
        XCTAssertEqual(TextCleanup.normalize("a\tb\t\tc  d\u{00A0}\u{00A0}e"), "a b c d e")
    }

    func testNormalizeOfWhitespaceOnlyIsEmpty() {
        XCTAssertEqual(TextCleanup.normalize("   "), "")
        XCTAssertEqual(TextCleanup.normalize(""), "")
    }

    // MARK: - Pipeline

    func testRunAppliesCustomWordsThenFillersThenNormalisation() {
        let result = TextCleanup.run(
            "  uh charge b is great and, um, open a i  ",
            customWords: ["ChargeBee", "OpenAI"],
            aliases: []
        )
        XCTAssertEqual(
            result,
            TextCleanup.Result(text: "ChargeBee great and, OpenAI", dictionaryFixes: 2)
        )
    }

    func testRunCountsOnlySubstitutionsThatChangedTheText() {
        XCTAssertEqual(
            TextCleanup.run("hello world", customWords: ["hello", "world"], aliases: []),
            TextCleanup.Result(text: "hello world", dictionaryFixes: 0)
        )
        XCTAssertEqual(
            TextCleanup.run("I said Handee, then handy and HANDEE again", customWords: ["Handy"], aliases: []),
            TextCleanup.Result(text: "I said Handy, then Handy and HANDY again", dictionaryFixes: 3)
        )
    }

    func testRunWithoutCustomWordsStillCleans() {
        XCTAssertEqual(
            TextCleanup.run("  So uhm I I I was  thinking ", customWords: [], aliases: []),
            TextCleanup.Result(text: "So I was thinking", dictionaryFixes: 0)
        )
    }

    // MARK: - actions.rs helpers

    func testBlankTranscriptionIsDetected() {
        XCTAssertTrue(TextCleanup.isBlank(""))
        XCTAssertTrue(TextCleanup.isBlank("   "))
        XCTAssertTrue(TextCleanup.isBlank("\t\n  \r\n"))
    }

    func testNonBlankTranscriptionIsKept() {
        XCTAssertFalse(TextCleanup.isBlank("hello"))
        XCTAssertFalse(TextCleanup.isBlank("  hello  "))
    }

    func testLeadingThinkBlockIsStripped() {
        XCTAssertEqual(
            TextCleanup.stripThinkBlock("<think>pondering...</think>Cleaned text."),
            "Cleaned text."
        )
        XCTAssertEqual(
            TextCleanup.stripThinkBlock("  \n<think>multi\nline</think>\n  Cleaned text."),
            "Cleaned text."
        )
    }

    func testContentWithoutThinkBlockIsUnchanged() {
        XCTAssertEqual(TextCleanup.stripThinkBlock("Cleaned text."), "Cleaned text.")
        XCTAssertEqual(
            TextCleanup.stripThinkBlock("Mentions <think> mid-sentence."),
            "Mentions <think> mid-sentence."
        )
        // Unclosed block: leave untouched rather than guess
        XCTAssertEqual(TextCleanup.stripThinkBlock("<think>never closed"), "<think>never closed")
    }

    // MARK: - Distance metrics

    func testLevenshteinMatchesStrsim() {
        XCTAssertEqual(TextCleanup.levenshtein("centrix", "zentryx"), 2)
        XCTAssertEqual(TextCleanup.levenshtein("handee", "handy"), 2)
        XCTAssertEqual(TextCleanup.levenshtein("chargebis", "chargebee"), 2)
        XCTAssertEqual(TextCleanup.levenshtein("kitten", "sitting"), 3)
        XCTAssertEqual(TextCleanup.levenshtein("", "abc"), 3)
        XCTAssertEqual(TextCleanup.levenshtein("abc", ""), 3)
        XCTAssertEqual(TextCleanup.levenshtein("", ""), 0)
        XCTAssertEqual(TextCleanup.levenshtein("rand", "randd"), 1)
    }

    func testSoundexMatchesNaturalCrate() {
        XCTAssertEqual(TextCleanup.soundexEncoding("handee"), "h530")
        XCTAssertEqual(TextCleanup.soundexEncoding("handy"), "h530")
        XCTAssertEqual(TextCleanup.soundexEncoding("chargebee"), "c621")
        XCTAssertEqual(TextCleanup.soundexEncoding("r"), "r000")
        XCTAssertEqual(TextCleanup.soundexEncoding(""), "0000")

        XCTAssertTrue(TextCleanup.soundex("handee", "handy"))
        XCTAssertTrue(TextCleanup.soundex("chargebis", "chargebee"))
        XCTAssertTrue(TextCleanup.soundex("rand", "randd"))
        XCTAssertTrue(TextCleanup.soundex("tymczak", "tymzak"))
        XCTAssertTrue(TextCleanup.soundex("ashcraft", "ashcroft"))
        // First letter is compared verbatim, so C/Z and P/B differ even though
        // textbook Soundex would merge P with the following F.
        XCTAssertFalse(TextCleanup.soundex("centrix", "zentryx"))
        XCTAssertFalse(TextCleanup.soundex("pfister", "bfister"))
        XCTAssertFalse(TextCleanup.soundex("a", "e"))
    }
}
