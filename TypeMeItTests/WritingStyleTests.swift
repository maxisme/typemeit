import XCTest
@testable import TypeMeIt

final class WritingStyleTests: XCTestCase {
    func testDigitsRewritesSmallNumbers() {
        XCTAssertEqual(WritingStyle.digits("We need one more chair and three tables."), "We need 1 more chair and 3 tables.")
        XCTAssertEqual(WritingStyle.digits("Grab a coffee and two croissants"), "Grab a coffee and 2 croissants")
    }

    func testDigitsJoinsCompoundNumbers() {
        XCTAssertEqual(WritingStyle.digits("twenty five people"), "25 people")
        XCTAssertEqual(WritingStyle.digits("Twenty-five people"), "25 people")
        XCTAssertEqual(WritingStyle.digits("one hundred and twenty pounds"), "120 pounds")
        XCTAssertEqual(WritingStyle.digits("two thousand and six"), "2006")
        XCTAssertEqual(WritingStyle.digits("three million"), "3000000")
        XCTAssertEqual(WritingStyle.digits("call one two three"), "call 1 2 3")
    }

    func testDigitsWritesOrdinals() {
        XCTAssertEqual(WritingStyle.digits("She came first and I came fourth."), "She came 1st and I came 4th.")
        XCTAssertEqual(WritingStyle.digits("the twenty first of June"), "the 21st of June")
        XCTAssertEqual(WritingStyle.digits("the twelfth time"), "the 12th time")
    }

    func testDigitsLeavesPronounOneAndSecond() {
        XCTAssertEqual(WritingStyle.digits("No one told me one of them left"), "No one told me one of them left")
        XCTAssertEqual(WritingStyle.digits("which one do you want"), "which one do you want")
        XCTAssertEqual(WritingStyle.digits("wait a second, and the second one"), "wait a second, and the second one")
        XCTAssertEqual(WritingStyle.digits("a hundred"), "a hundred")
        XCTAssertEqual(WritingStyle.digits("and then we left"), "and then we left")
    }

    func testCutFillersDropsOnlyMeaninglessOnes() {
        XCTAssertEqual(WritingStyle.cutFillers("So it was, you know, really good and we should basically do it again."), "So it was really good and we should do it again.")
        XCTAssertEqual(WritingStyle.cutFillers("You know, I think we should go."), "I think we should go.")
        XCTAssertEqual(WritingStyle.cutFillers("I like the blue one. Basically done."), "I like the blue one. Done.")
        XCTAssertEqual(WritingStyle.cutFillers("I mean it."), "It.")
    }

    func testNumberedListSplitsSpokenCounters() {
        XCTAssertEqual(WritingStyle.numberedList("Okay so three things for tomorrow. First we need to finish the landing page. Second, call the accountant. And third, book the tickets."),
                       "Okay so three things for tomorrow.\n1. We need to finish the landing page.\n2. Call the accountant.\n3. Book the tickets.")
        XCTAssertEqual(WritingStyle.numberedList("First, plug it in. Secondly, turn it on."), "1. Plug it in.\n2. Turn it on.")
    }

    func testNumberedListLeavesProseAlone() {
        XCTAssertEqual(WritingStyle.numberedList("She came first and I came fourth."), "She came first and I came fourth.")
        XCTAssertEqual(WritingStyle.numberedList("First, the good news."), "First, the good news.")
        XCTAssertEqual(WritingStyle.numberedList("Second, wait. First, no."), "Second, wait. First, no.")
    }

    func testApplyLowercasesLast() {
        XCTAssertEqual(WritingStyle.apply([.fillerWords, .digits, .lowercase], to: "Basically Sam brought three."), "sam brought 3.")
        XCTAssertEqual(WritingStyle.apply([], to: "Unchanged Text"), "Unchanged Text")
    }

    func testRulesOnlyCoverModelStyles() {
        XCTAssertNil(WritingStyle.rules([.digits, .lowercase, .lists]))
        XCTAssertEqual(WritingStyle.rules([.contractions]), "The user also wants these, applied to the whole transcript:\n- " + WritingStyle.contractions.rule!)
    }
}
