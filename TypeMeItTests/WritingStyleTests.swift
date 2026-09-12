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
        XCTAssertEqual(WritingStyle.digits("my number is oh seven seven one two three four five six seven"), "my number is 0771234567")
        XCTAssertEqual(WritingStyle.digits("oh no, seven of them"), "oh no, 7 of them")
    }

    func testDigitsWritesOrdinals() {
        XCTAssertEqual(WritingStyle.digits("She came first and I came fourth."), "She came 1st and I came 4th.")
        XCTAssertEqual(WritingStyle.digits("the twenty first of June"), "the 21st of June")
        XCTAssertEqual(WritingStyle.digits("the twelfth time"), "the 12th time")
    }

    func testDigitsLeavesPronounOneAndSecond() {
        XCTAssertEqual(WritingStyle.digits("No one told me one of them left"), "No one told me one of them left")
        XCTAssertEqual(WritingStyle.digits("which one do you want"), "which one do you want")
        XCTAssertEqual(WritingStyle.digits("wait a second, give me a second"), "wait a second, give me a second")
        XCTAssertEqual(WritingStyle.digits("a hundred percent yes and a thousand more"), "100% yes and 1000 more")
        XCTAssertEqual(WritingStyle.digits("the second session and the second one"), "the 2nd session and the 2nd one")
        XCTAssertEqual(WritingStyle.digits("and then we left"), "and then we left")
    }

    func testCutFillersDropsOnlyMeaninglessOnes() {
        XCTAssertEqual(WritingStyle.cutFillers("So it was, you know, really good and we should basically do it again."), "So it was really good and we should do it again.")
        XCTAssertEqual(WritingStyle.cutFillers("You know, I think we should go."), "I think we should go.")
        XCTAssertEqual(WritingStyle.cutFillers("I like the blue one. Basically done."), "I like the blue one. Done.")
        XCTAssertEqual(WritingStyle.cutFillers("I mean it."), "It.")
        XCTAssertEqual(WritingStyle.cutFillers("You know what I mean, it was fine."), "It was fine.")
        XCTAssertEqual(WritingStyle.cutFillers("it was fine you know"), "It was fine")
    }

    func testCutFillersKeepsRealPhrases() {
        XCTAssertEqual(WritingStyle.cutFillers("Do you know what time it is?"), "Do you know what time it is?")
        XCTAssertEqual(WritingStyle.cutFillers("If you know the answer, say so."), "If you know the answer, say so.")
        XCTAssertEqual(WritingStyle.cutFillers("It looks like rain. I like it."), "It looks like rain. I like it.")
        XCTAssertEqual(WritingStyle.cutFillers("Not the actual deploy."), "Not the actual deploy.")
    }

    func testCutFillersCutsLikeAndActually() {
        XCTAssertEqual(WritingStyle.cutFillers("It was like really cold."), "It was really cold.")
        XCTAssertEqual(WritingStyle.cutFillers("It's kind of late and sort of a waste for that kind of person."), "It's late and sort of a waste for that kind of person.")
        XCTAssertEqual(WritingStyle.cutFillers("Like I don't even know."), "I don't even know.")
        XCTAssertEqual(WritingStyle.cutFillers("I actually think so. Actually, no."), "I think so. No.")
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

    func testNumberedListIgnoresOrdinalsAfterDeterminers() {
        XCTAssertEqual(WritingStyle.numberedList("first we wait for the second review and second they sign"),
                       "1. We wait for the second review\n2. They sign")
    }

    func testNumberedListWorksWithoutPunctuation() {
        XCTAssertEqual(WritingStyle.numberedList("two things first the build is red and second the notes are missing"),
                       "Two things\n1. The build is red\n2. The notes are missing")
        XCTAssertEqual(WritingStyle.numberedList("first um preheat the oven secondly mix the flour"), "1. Preheat the oven\n2. Mix the flour")
        XCTAssertEqual(WritingStyle.numberedList("Okay, two things first. We wait, and second, they sign."), "Okay, two things.\n1. We wait.\n2. They sign.")
        XCTAssertEqual(WritingStyle.numberedList("we came second in the league and first in the cup"), "we came second in the league and first in the cup")
    }

    func testContractJoinsSafePairs() {
        XCTAssertEqual(WritingStyle.contract("I am not sure that is going to work."), "I'm not sure that's going to work.")
        XCTAssertEqual(WritingStyle.contract("You are right, it does not matter. We will see."), "You're right, it doesn't matter. We'll see.")
        XCTAssertEqual(WritingStyle.contract("He would have called if he could not make it."), "He would've called if he couldn't make it.")
        XCTAssertEqual(WritingStyle.contract("I cannot believe it is Friday. Do not go."), "I can't believe it's Friday. Don't go.")
        XCTAssertEqual(WritingStyle.contract("It is not that we will not go; she is not here."), "It's not that we won't go; she's not here.")
    }

    func testContractLeavesAmbiguousOnes() {
        XCTAssertEqual(WritingStyle.contract("That is what it is."), "That's what it is.")
        XCTAssertEqual(WritingStyle.contract("Here I am."), "Here I am.")
        XCTAssertEqual(WritingStyle.contract("She has a car. Let us know."), "She has a car. Let us know.")
        XCTAssertEqual(WritingStyle.contract("She has finished and he has gone."), "She's finished and he's gone.")
        XCTAssertEqual(WritingStyle.contract("That is where we are with it and how they are doing."), "That's where we are with it and how they are doing.")
    }

    func testDigitsWritesPercent() {
        XCTAssertEqual(WritingStyle.digits("ten percent off the red one"), "10% off the red one")
        XCTAssertEqual(WritingStyle.digits("the first one is cheaper"), "the 1st one is cheaper")
        XCTAssertEqual(WritingStyle.digits("two things first we wait and second they sign"), "2 things first we wait and second they sign")
        XCTAssertEqual(WritingStyle.digits("it closes at five thirty and opens at eight"), "it closes at 5:30 and opens at 8")
        XCTAssertEqual(WritingStyle.digits("First, we wait. And second, they sign. She came first, I came fourth."), "First, we wait. And second, they sign. She came 1st, I came 4th.")
    }

    func testApplyLowercasesLast() {
        XCTAssertEqual(WritingStyle.apply([.fillerWords, .digits, .lowercase], to: "Basically Sam brought three."), "sam brought 3.")
        XCTAssertEqual(WritingStyle.apply([.lowercase], to: "Hey Sam, I will send the report to John on Monday. OK?"), "hey sam, i will send the report to john on monday. ok?")
        XCTAssertEqual(WritingStyle.apply([.lowercase, .lists, .contractions], to: "Two things. First, I am in. Second, you are out."), "two things.\n1. i'm in.\n2. you're out.")
        XCTAssertEqual(WritingStyle.apply([], to: "Unchanged Text"), "Unchanged Text")
    }

    func testRulesOnlyCoverModelStyles() {
        XCTAssertNil(WritingStyle.rules([.digits, .lowercase, .lists]))
        XCTAssertEqual(WritingStyle.rules([.contractions]), "The user also wants these, applied to the whole transcript:\n- " + WritingStyle.contractions.rule!)
    }
}
