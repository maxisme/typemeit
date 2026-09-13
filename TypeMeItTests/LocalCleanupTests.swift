import XCTest
@testable import TypeMeIt

final class LocalCleanupTests: XCTestCase {
    func testMidSentenceFillerInPunctuatedText() {
        XCTAssertEqual(LocalCleanup.run("Remove uh the subcopy. Is there any other subcopy?"), "Remove the subcopy. Is there any other subcopy?")
    }

    func testFillerTakesItsOwnPunctuation() {
        XCTAssertEqual(LocalCleanup.run("Well, uhm, I think, uh. that's right"), "Well, I think, that's right")
        XCTAssertEqual(LocalCleanup.run("that's it um. Next"), "that's it. Next")
    }

    func testCaseInsensitive() {
        XCTAssertEqual(LocalCleanup.run("Um so UH yes"), "so yes")
    }

    func testWordBoundaries() {
        XCTAssertEqual(LocalCleanup.run("ham hum humm uhmm"), "ham hum humm")
    }

    func testInterjectionsStay() {
        XCTAssertEqual(LocalCleanup.run("nice, eh? Uh! Really"), "nice, eh? Uh! Really")
    }

    func testUnitsAreNotFillers() {
        XCTAssertEqual(LocalCleanup.run("about 5 mm wide"), "about 5 mm wide")
    }

    func testFillerOnlyIsEmpty() {
        XCTAssertEqual(LocalCleanup.run("um, uh uh."), "")
    }

    func testStutterCollapses() {
        XCTAssertEqual(LocalCleanup.run("I I I think we we should"), "I think we we should")
    }

    func testStutterKeepsClosingPunctuation() {
        XCTAssertEqual(LocalCleanup.run("Go go go, now"), "Go, now")
    }

    func testStutterAcrossFiller() {
        XCTAssertEqual(LocalCleanup.run("the the uh the plan"), "the plan")
    }

    func testNumbersDoNotCollapse() {
        XCTAssertEqual(LocalCleanup.run("1 1 1 2"), "1 1 1 2")
    }

    func testWhitespaceCollapsesAndTrims() {
        XCTAssertEqual(LocalCleanup.run("  so   many\t\tspaces \n"), "so many spaces")
    }

    func testPunctuatedRepeatsStay() {
        XCTAssertEqual(LocalCleanup.run("No. No. No, wait"), "No. No. No, wait")
    }

    func testQuotedFillerStays() {
        XCTAssertEqual(LocalCleanup.run("\"um, well\""), "\"um, well\"")
    }

    func testLineBreaksAreKept() {
        XCTAssertEqual(LocalCleanup.run("first uh line\nsecond   line\n"), "first line\nsecond line")
    }

    func testErIsAFiller() {
        XCTAssertEqual(LocalCleanup.run("it was er, erm, fine"), "it was fine")
    }

    func testElongatedFillers() {
        XCTAssertEqual(LocalCleanup.run("so uhhhh ummmm hmmmm errrm yes"), "so yes")
    }

    func testUhOhIsAPhrase() {
        XCTAssertEqual(LocalCleanup.run("uh oh, that's bad. uh, oh well"), "uh oh, that's bad. oh well")
    }

    func testEdgeCases() {
        let cases: [(String, String)] = [
            ("um, so we go", "so we go"),
            ("don't don't don't stop", "don't don't don't stop"),
            ("well-known well-known well-known", "well-known well-known well-known"),
            ("(I I I)", "(I)"),
            ("very very good", "very very good"),
            ("wait — uh — no", "wait — — no"),
            ("so... uh... yes", "so... uh... yes"),
            ("one\r\ntwo", "one\ntwo"),
            ("first\n\nsecond", "first\n\nsecond"),
            ("um\nhi", "hi"),
            ("2 2 2 mm", "2 2 2 mm"),
            ("Ah, Ahh, AHHH. done", "done"),
            ("ha ha ha funny", "funny"),
            ("Uh oh", "Uh oh"),
            ("", ""),
            ("   ", ""),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(LocalCleanup.run(input), expected, "input: \(input.debugDescription)")
        }
    }
}
