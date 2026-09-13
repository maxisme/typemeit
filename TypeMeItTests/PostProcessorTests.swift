import XCTest
@testable import TypeMeIt

final class PostProcessorTests: XCTestCase {
    func testLostOpeningRejectsADroppedStart() {
        XCTAssertTrue(PostProcessor.lostOpening(transcript: "that will be $25 please", output: "$25 please."))
        XCTAssertTrue(PostProcessor.lostOpening(transcript: "so I think we should ship it", output: "We should ship it on Friday."))
    }

    func testLostOpeningAllowsOneAddedWordAndPunctuation() {
        XCTAssertFalse(PostProcessor.lostOpening(transcript: "that will be $25 please", output: "That will be $25, please."))
        XCTAssertFalse(PostProcessor.lostOpening(transcript: "what is the time", output: "Hey, what is the time?"))
        XCTAssertFalse(PostProcessor.lostOpening(transcript: "", output: "anything"))
        XCTAssertFalse(PostProcessor.lostOpening(transcript: "their going to the shops", output: "They're going to the shops."))
        XCTAssertFalse(PostProcessor.lostOpening(transcript: "were meeting at there house", output: "We're meeting at their house."))
    }

    func testJoinSpelledLettersMakesAcronyms() {
        XCTAssertEqual(ModelText.joinSpelledLetters("lottie h q signed with anthropic"), "lottie HQ signed with anthropic")
        XCTAssertEqual(ModelText.joinSpelledLetters("send it as a p d f to the c e o"), "send it as a PDF to the CEO")
        XCTAssertEqual(ModelText.joinSpelledLetters("I don't f a little bit"), "I don't f a little bit")
        XCTAssertEqual(ModelText.joinSpelledLetters("a b test and I a m"), "a b test and I a m")
    }

    func testFuseTermsJoinsSpokenWordsIntoATerm() {
        XCTAssertEqual(ModelText.fuseTerms("Lottie HQ signed with Anthropic.", terms: ["LottieHQ", "Anthropic"]), "LottieHQ signed with Anthropic.")
        XCTAssertEqual(ModelText.fuseTerms("Bump max retries to 5 in parse config.", terms: ["MAX_RETRIES", "parse_config.ts", "parse_config"]), "Bump MAX_RETRIES to 5 in parse_config.")
        XCTAssertEqual(ModelText.fuseTerms("use the state hook", terms: ["useState"]), "use the state hook")
    }

    func testCurrencySymbols() {
        XCTAssertEqual(ModelText.currencySymbols("That will be 25 dollars and 3.50 euros, not 50 pounds."), "That will be $25 and €3.50, not £50.")
    }
}
