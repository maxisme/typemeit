import XCTest
@testable import TypeMeIt

final class ScreenContextTests: XCTestCase {
    private let dictionary: Set<String> = ["the", "meeting", "with", "on", "monday", "about", "is", "at", "and", "please", "review", "this", "for", "me", "return", "raw", "const", "state", "null", "aubergine"]
    private func known(_ w: String) -> Bool { dictionary.contains(w) }

    func testKeepsNamesAndJargonAndDropsDictionaryWords() {
        let lines = ["The meeting with Zentryx on monday", "please review PR-1234 for me", "Kavuu is at GitHub and @maxisme"]
        XCTAssertEqual(
            ScreenContext.terms(from: lines, isKnownWord: known),
            ["@maxisme", "GitHub", "Kavuu", "PR-1234", "Zentryx"]
        )
    }

    func testCapitalisedWordsAfterTheFirstAreNamesEvenWhenTheDictionaryKnowsThem() {
        let lines = ["Tomasz Wieczorek  10:44", "Meeting with Grace about the review", "The meeting"]
        let known: (String) -> Bool = { ["tomasz", "wieczorek", "meeting", "with", "grace", "about", "the", "review"].contains($0) }
        XCTAssertEqual(ScreenContext.terms(from: lines, isKnownWord: known), ["Grace", "Tomasz", "Wieczorek"])
    }

    func testCodePunctuationSplitsTokens() {
        let lines = ["return fetchUser(raw, MAX_RETRIES)", "const [state, setState] = useState<Config | null>(null)", "Ottolenghi's aubergine"]
        XCTAssertEqual(ScreenContext.terms(from: lines, isKnownWord: known), ["Config", "MAX_RETRIES", "Ottolenghi", "fetchUser", "setState", "useState"])
    }

    func testOrdersByFrequencyThenAlphabetically() {
        let lines = ["Kavuu Zentryx", "Zentryx", "Aardvarkish"]
        XCTAssertEqual(ScreenContext.terms(from: lines, isKnownWord: known), ["Zentryx", "Aardvarkish", "Kavuu"])
    }

    func testExcludesCustomWordsAndDedupesCaseInsensitively() {
        let lines = ["zentryx Zentryx", "Kavuu"]
        XCTAssertEqual(ScreenContext.terms(from: lines, excluding: ["kavuu"], isKnownWord: known), ["zentryx"])
    }

    func testRejectsUrlsPathsNumbersAndPunctuation() {
        let lines = ["https://example.com/foo", "~/Documents/repos", "12:30", "42", "—", "a", "(Zentryx),"]
        XCTAssertEqual(ScreenContext.terms(from: lines, isKnownWord: known), ["Zentryx"])
    }

    func testCapsAtMaxTerms() {
        let lines = (0..<100).map { "Term\($0)x" }
        XCTAssertEqual(ScreenContext.terms(from: lines, isKnownWord: known).count, ScreenContext.maxTerms)
    }

    func testShapeAloneMakesACandidate() {
        XCTAssertTrue(ScreenContext.isCandidate("iPhone", isKnownWord: { _ in true }))
        XCTAssertTrue(ScreenContext.isCandidate("NASA", isKnownWord: { _ in true }))
        XCTAssertTrue(ScreenContext.isCandidate("McDonald", isKnownWord: { _ in true }))
        XCTAssertTrue(ScreenContext.isCandidate("H2O", isKnownWord: { _ in true }))
        XCTAssertFalse(ScreenContext.isCandidate("Monday", isKnownWord: { _ in true }))
        XCTAssertFalse(ScreenContext.isCandidate("monday", isKnownWord: { _ in true }))
    }

    func testCodeIdentifiersAreCandidatesEvenWhenTheirPartsAreWords() {
        let parts: Set<String> = ["parse", "config", "user", "name", "well", "known", "screen", "context", "max", "retries"]
        let known: (String) -> Bool = { parts.contains($0) || $0 == "parse_config" || $0 == "user.name" || $0 == "well-known" || $0 == "screen-context" }
        XCTAssertTrue(ScreenContext.isCandidate("parse_config", isKnownWord: known))
        XCTAssertTrue(ScreenContext.isCandidate("user.name", isKnownWord: known))
        XCTAssertTrue(ScreenContext.isCandidate("MAX_RETRIES", isKnownWord: known))
        XCTAssertTrue(ScreenContext.isCandidate("kebab-zentryx", isKnownWord: known))
        XCTAssertFalse(ScreenContext.isCandidate("well-known", isKnownWord: known))
        XCTAssertFalse(ScreenContext.isCandidate("screen-context", isKnownWord: known))
    }

    func testFunctionCallsLoseTheirParentheses() {
        XCTAssertEqual(ScreenContext.clean("parseConfig()"), "parseConfig")
        XCTAssertEqual(ScreenContext.clean("self.settings,"), "self.settings")
        XCTAssertNil(ScreenContext.clean("a.b.c"))
        XCTAssertEqual(ScreenContext.terms(from: ["see https://x.dev/a and ~/repos/hulk"], isKnownWord: { _ in true }), [])
    }

    func testInstructionsCarryScreenTermsAfterCustomWords() {
        let p = PostProcessor.instructions(customWords: ["Kavuu"], screenTerms: ["Zentryx", "GitHub"])
        XCTAssertEqual(p, PostProcessor.instructions
            + "\n\nTerms this user says often, with their exact spelling:\nKavuu\n\nIf a word or phrase in the transcript is a mishearing of one of these terms, replace it with the exact spelling above. Do not change anything else because of this list."
            + "\n\nNames and terms that were on the user's screen while they spoke, with their exact spelling:\nZentryx, GitHub\n\nThe speech-to-text model does not know these terms, so it writes what they sound like, often as several ordinary words (\"cube control\" for kubectl, \"use state\" for useState, \"centrics\" for Zentryx). Where a word or run of words in the transcript sounds like one of these terms, replace it with the exact spelling above. Do not add a term the transcript does not say, and do not change anything else because of this list.")
    }

    func testInstructionsUnchangedWithoutLists() {
        XCTAssertEqual(PostProcessor.instructions(customWords: []), PostProcessor.instructions)
    }
}
