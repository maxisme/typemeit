import XCTest
@testable import TypeMeIt

final class CustomWordMatcherTests: XCTestCase {
    private let terms = ["typeme.it", "Eliza", "lottie.org", "ack", "fucking", "lib"]

    private func run(_ text: String, confidence: [String: Float] = [:], terms: [String]? = nil) -> CustomWordMatcher.Outcome {
        let words = text.split(separator: " ").map { CustomWordMatcher.Word(text: String($0), confidence: confidence[String($0)]) }
        return CustomWordMatcher.apply(words, terms: terms ?? self.terms)
    }

    func testARunSpellingTheTermIsJoined() {
        XCTAssertEqual(run("When I said type me it, it wrote nothing"), .init(text: "When I said typeme.it, it wrote nothing", fixes: 1))
    }

    func testAJoinedRunKeepsItsConfidenceOutOfIt() {
        XCTAssertEqual(run("say type me it now", confidence: ["type": 0.99, "me": 0.99, "it": 0.99]).text, "say typeme.it now")
    }

    func testListedWordsAreNeverTradedForAnotherTerm() {
        XCTAssertEqual(run("Surely there's a fucking lib for this"), .init(text: "Surely there's a fucking lib for this", fixes: 0))
    }

    func testAShortTermMatchesOnlyExactly() {
        XCTAssertEqual(run("let's do the RAF rate limit", confidence: ["RAF": 0.5]).fixes, 0)
    }

    func testCaseIsCorrectedToTheTermsSpelling() {
        XCTAssertEqual(run("ask eliza about it"), .init(text: "ask Eliza about it", fixes: 1))
    }

    func testAnAlreadyCorrectTermIsNotCounted() {
        XCTAssertEqual(run("ask Eliza about typeme.it"), .init(text: "ask Eliza about typeme.it", fixes: 0))
    }

    func testAnUncertainSoundalikeIsReplaced() {
        XCTAssertEqual(run("changed to TypeMeet", confidence: ["TypeMeet": 0.68]).text, "changed to typeme.it")
        XCTAssertEqual(run("send it to loti", confidence: ["loti": 0.73], terms: ["Lottie"]).text, "send it to Lottie")
    }

    func testAConfidentSoundalikeBecomesAHintForTheModel() {
        XCTAssertEqual(run("changed to TypeMeet", confidence: ["TypeMeet": 0.98]),
                       .init(text: "changed to TypeMeet", fixes: 0, hints: [.init(heard: "TypeMeet", term: "typeme.it")]))
        XCTAssertEqual(run("check if whisper is running", confidence: ["whisper": 0.99], terms: ["wispr"]).hints,
                       [.init(heard: "whisper", term: "wispr")])
    }

    func testAShortConfidentWordIsNotEvenHinted() {
        XCTAssertEqual(run("the cat sat", confidence: ["cat": 0.99], terms: ["cut"]), .init(text: "the cat sat", fixes: 0))
    }

    func testAnUnknownConfidenceCountsAsUncertain() {
        XCTAssertEqual(run("changed to TypeMeet").text, "changed to typeme.it")
    }

    func testAMishearingTooFarFromTheTermIsLeftAsHeard() {
        XCTAssertEqual(run("Why did it get changed to Titemere", confidence: ["Titemere": 0.74]).fixes, 0)
    }

    func testPunctuationAroundTheRunSurvives() {
        XCTAssertEqual(run("(type me it), then").text, "(typeme.it), then")
    }

    func testDoubledLettersKeyLikeSingleOnes() {
        XCTAssertEqual(run("ping maxo about the blebird release", terms: ["Maxxo", "Bluebird"]).text, "ping Maxxo about the Bluebird release")
    }

    func testPresentTermsAreTheOnesSpelledAsListed() {
        XCTAssertEqual(CustomWordMatcher.present(in: "a fucking lib, and typeme.it.", terms: terms), ["typeme.it", "fucking", "lib"])
        XCTAssertEqual(CustomWordMatcher.present(in: "ask eliza", terms: terms), [])
    }

    func testSoundKeys() {
        XCTAssertEqual(CustomWordMatcher.soundKey("typemeit"), "tpmt")
        XCTAssertEqual(CustomWordMatcher.soundKey("typemeet"), "tpmt")
        XCTAssertEqual(CustomWordMatcher.soundKey("kubectl"), "kbktl")
        XCTAssertEqual(CustomWordMatcher.soundKey("cubecontrol"), "kbkntrl")
        XCTAssertEqual(CustomWordMatcher.soundKey("philip"), "flp")
    }

    func testScoredWordsAttachWhenTheyLineUp() {
        let scored = [Transcriber.Word(text: "hello", confidence: 0.9, start: .zero, end: .zero),
                      Transcriber.Word(text: "world", confidence: .nan, start: .zero, end: .zero)]
        XCTAssertEqual(Transcriber.Transcript(text: "hello world", words: scored).matcherWords,
                       [.init(text: "hello", confidence: 0.9), .init(text: "world", confidence: nil)])
        XCTAssertEqual(Transcriber.Transcript(text: "hello there world", words: scored).matcherWords.map(\.confidence), [nil, nil, nil])
    }
}
