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
}
