import Foundation
import XCTest

@testable import TypeMeIt

/// Answers with a fixed list, recording what it was asked.
private final class Scripted: VocabularyCheck, @unchecked Sendable {
    struct Failure: Error, Equatable {
        let reason: String
    }

    private let answer: Result<[CorrectionKind], Failure>
    private let lock = NSLock()
    private var asked: [[Candidate]] = []

    init(_ answer: Result<[CorrectionKind], Failure>) {
        self.answer = answer
    }

    convenience init(kinds: [CorrectionKind]) {
        self.init(.success(kinds))
    }

    convenience init(failing reason: String) {
        self.init(.failure(Failure(reason: reason)))
    }

    var calls: Int {
        lock.withLock { asked.count }
    }

    var firstAsked: [Candidate] {
        lock.withLock { asked.first ?? [] }
    }

    func check(_ candidates: [Candidate], context: String) async throws -> [CorrectionKind] {
        lock.withLock { asked.append(candidates) }
        return try answer.get()
    }
}

private func hunk(_ removed: String, _ inserted: String) -> Hunk {
    Hunk(
        removed: removed.split(whereSeparator: \.isWhitespace).map(String.init),
        inserted: inserted.split(whereSeparator: \.isWhitespace).map(String.init)
    )
}

private func meants(_ learned: [LearnedPair]) -> [String] {
    learned.map(\.meant)
}

// MARK: - mod.rs

final class LearningEngineTests: XCTestCase {
    func testTermTokensPickAcronymsAndProductNamesOutOfOrdinaryWords() {
        XCTAssertEqual(Learning.termTokens("can CI/CD"), ["CI/CD"])
        XCTAssertEqual(Learning.termTokens("the iPhone, please"), ["iPhone"])
        XCTAssertEqual(Learning.termTokens("use K8s here"), ["K8s"])
        XCTAssertTrue(Learning.termTokens("do this package export").isEmpty)
        XCTAssertTrue(Learning.termTokens("Send it today").isEmpty)
    }

    func testLearnsOnlyPairsTheModelCallsVocabulary() async {
        let check = Scripted(kinds: [.productOrCompany, .rewording])
        let learned = await Learning.learn(
            original: "We moved billing to Charge B and it went fine",
            edited: "We moved billing to ChargeBee and it worked fine",
            context: LearnContext(),
            check: check
        )
        XCTAssertEqual(learned, [LearnedPair(heard: "Charge B", meant: "ChargeBee")])
        XCTAssertEqual(check.calls, 1)
    }

    func testOneCallCarriesEveryCandidate() async {
        let check = Scripted(kinds: [.personName, .projectOrService])
        let learned = await Learning.learn(
            original: "Ask pree yanka to move the zen tricks data",
            edited: "Ask Priyanka to move the Zentrix data",
            context: LearnContext(),
            check: check
        )
        XCTAssertEqual(meants(learned), ["Priyanka", "Zentrix"])
        XCTAssertEqual(check.firstAsked.count, 2)
    }

    func testNothingLearnableMeansNoModelCall() async {
        let check = Scripted(kinds: [])
        let caseOnly = await Learning.learn(
            original: "I think typeme is good",
            edited: "I think Typeme is good",
            context: LearnContext(),
            check: check
        )
        XCTAssertTrue(caseOnly.isEmpty)
        let insertion = await Learning.learn(
            original: "send the report",
            edited: "send the full report",
            context: LearnContext(),
            check: check
        )
        XCTAssertTrue(insertion.isEmpty)
        XCTAssertEqual(check.calls, 0)
    }

    func testModelFailureLearnsNothing() async {
        let failing = Scripted(failing: "offline")
        let failed = await Learning.learn(
            original: "Charge B", edited: "ChargeBee", context: LearnContext(), check: failing
        )
        XCTAssertTrue(failed.isEmpty)
        let empty = Scripted(kinds: [])
        let unanswered = await Learning.learn(
            original: "Charge B", edited: "ChargeBee", context: LearnContext(), check: empty
        )
        XCTAssertTrue(unanswered.isEmpty)
    }

    func testKnownAndDeniedWordsAreNeverAskedAbout() async {
        let check = Scripted(kinds: [])
        let learned = await Learning.learn(
            original: "billing on Charge B, staging on by frost",
            edited: "billing on ChargeBee, staging on Bifrost",
            context: LearnContext(customWords: ["ChargeBee"], denylist: ["Bifrost"]),
            check: check
        )
        XCTAssertTrue(learned.isEmpty)
        XCTAssertEqual(check.calls, 0)
    }

    func testACapitalisedMidSentenceWordOverridesACommonWordVerdict() async {
        let check = Scripted(kinds: [.commonWord])
        let learned = await Learning.learn(
            original: "Load it into kah voo.",
            edited: "Load it into Kavuu.",
            context: LearnContext(),
            check: check
        )
        XCTAssertEqual(meants(learned), ["Kavuu"])
    }

    func testATermInsideARewordingIsLearnedOnItsOwn() async {
        let check = Scripted(kinds: [.rewording])
        let learned = await Learning.learn(
            original: "NCI C D do this package export",
            edited: "can CI/CD do this package export",
            context: LearnContext(),
            check: check
        )
        XCTAssertEqual(meants(learned), ["CI/CD"])
    }

    func testOrdinaryWordsJudgedCommonAreNotLearned() async {
        let singular = await Learning.learn(
            original: "Send a notifications to the team.",
            edited: "Send a notification to the team.",
            context: LearnContext(),
            check: Scripted(kinds: [.commonWord])
        )
        XCTAssertTrue(singular.isEmpty)
        let agreement = await Learning.learn(
            original: "Notifications go to the team.",
            edited: "Notification goes to the team.",
            context: LearnContext(),
            check: Scripted(kinds: [.commonWord])
        )
        XCTAssertTrue(agreement.isEmpty)
    }

    func testCoinedWordsAreLearnedEvenAtSentenceStart() async throws {
        try XCTSkipIf(WordList.system.isEmpty, "no system word list at /usr/share/dict/words")
        let sentenceStart = await Learning.learn(
            original: "Zentrix is the new staging cluster",
            edited: "Zentryx is the new staging cluster",
            context: LearnContext(),
            check: Scripted(kinds: [.commonWord])
        )
        XCTAssertEqual(meants(sentenceStart), ["Zentryx"])
        let lowercase = await Learning.learn(
            original: "Load it into kah voo.",
            edited: "Load it into kavuu.",
            context: LearnContext(),
            check: Scripted(kinds: [.commonWord])
        )
        XCTAssertEqual(meants(lowercase), ["kavuu"])
    }

    func testProperNounShape() {
        XCTAssertTrue(Learning.writtenAsProperNoun("Ostrava", in: "The Ostrava service handles enquiries."))
        XCTAssertTrue(Learning.writtenAsProperNoun("MacBook Pro", in: "My MacBook Pro needs a restart."))
        XCTAssertFalse(Learning.writtenAsProperNoun("Ostrava", in: "Ostrava handles it."))
        XCTAssertFalse(Learning.writtenAsProperNoun("ostrava", in: "The ostrava service."))
        XCTAssertFalse(Learning.writtenAsProperNoun("SDK", in: "Update the SDK first."))
        XCTAssertFalse(Learning.writtenAsProperNoun("GPT4", in: "Use GPT4 for this."))
        XCTAssertFalse(Learning.writtenAsProperNoun("Ostrava", in: "Fine. Ostrava handles it."))
    }

    func testARewriteYieldsNoCandidates() {
        let original = "one two three four five six seven eight nine ten eleven twelve"
        let edited = "a b c d e f g h i j k l"
        XCTAssertTrue(Learning.candidates(original: original, edited: edited, context: LearnContext()).isEmpty)
    }

    func testAtMostFourCandidatesPerEdit() {
        let original = "aa1 x bb1 x cc1 x dd1 x ee1"
        let edited = "Alpha x Bravo x Charlie x Delta x Echo"
        XCTAssertEqual(Learning.candidates(original: original, edited: edited, context: LearnContext()).count, 4)
    }

    func testNormalizeMatchesCustomWordsInput() {
        XCTAssertEqual(Learning.normalizeWord("  <Charge\"Bee>  Pro "), "ChargeBee Pro")
    }
}

// MARK: - diff.rs

final class LearningDiffTests: XCTestCase {
    private func replacements(_ original: String, _ edited: String) -> [(String, String)] {
        Prefilter.hunks(original: original, edited: edited)!
            .filter(\.isReplacement)
            .map { ($0.removed.joined(separator: " "), $0.inserted.joined(separator: " ")) }
    }

    func testIdenticalTextHasNoHunks() {
        XCTAssertEqual(Prefilter.hunks(original: "we moved billing", edited: "we moved billing"), [])
    }

    func testSingleWordReplacement() {
        let found = replacements(
            "moved billing to Charge B last week",
            "moved billing to ChargeBee last week"
        )
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].0, "Charge B")
        XCTAssertEqual(found[0].1, "ChargeBee")
    }

    func testPunctuationAndCaseAloneAreNotChanges() {
        XCTAssertEqual(Prefilter.hunks(original: "hello world", edited: "Hello, world."), [])
    }

    func testInsertionAndDeletionAreNotReplacements() {
        let inserted = Prefilter.hunks(original: "send the report", edited: "send the full report")!
        XCTAssertEqual(inserted.count, 1)
        XCTAssertFalse(inserted[0].isReplacement)
        let deleted = Prefilter.hunks(original: "send the full report", edited: "send the report")!
        XCTAssertEqual(deleted.count, 1)
        XCTAssertFalse(deleted[0].isReplacement)
    }

    func testMultipleReplacementsStaySeparate() {
        let found = replacements(
            "Ask pree yanka to move the zen tricks data",
            "Ask Priyanka to move the Zentrix data"
        )
        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(found[0].0, "pree yanka")
        XCTAssertEqual(found[0].1, "Priyanka")
        XCTAssertEqual(found[1].0, "zen tricks")
        XCTAssertEqual(found[1].1, "Zentrix")
    }

    func testTooLongIsNil() {
        let long = Array(repeating: "word", count: Prefilter.maxDiffTokens + 1).joined(separator: " ")
        XCTAssertNil(Prefilter.hunks(original: long, edited: "word"))
    }
}

// MARK: - prefilter.rs

final class PrefilterTests: XCTestCase {
    func testPlainReplacementBecomesACandidate() {
        XCTAssertEqual(
            Prefilter.candidate(hunk("Charge B,", "ChargeBee,"), knownKeys: [], deniedKeys: []),
            .success(Candidate(heard: "Charge B", meant: "ChargeBee"))
        )
    }

    func testInnerPunctuationSurvivesTrimming() throws {
        let rAndD = try Prefilter.candidate(hunk("R and D", "R&D."), knownKeys: [], deniedKeys: []).get()
        XCTAssertEqual(rAndD.meant, "R&D")
        let gpt = try Prefilter.candidate(hunk("GPT four", "GPT-4,"), knownKeys: [], deniedKeys: []).get()
        XCTAssertEqual(gpt.meant, "GPT-4")
    }

    func testJoinsAndSplitsAreCandidates() throws {
        // Case and punctuation-only edits never produce a hunk (the diff
        // compares per-token keys), so a hunk whose joined keys match is a
        // spacing change: spelled-out acronyms and compound names.
        let cicd = try Prefilter.candidate(hunk("c i c d", "CI/CD,"), knownKeys: [], deniedKeys: []).get()
        XCTAssertEqual(cicd.meant, "CI/CD")
        let macBook = try Prefilter.candidate(hunk("mac book", "MacBook"), knownKeys: [], deniedKeys: []).get()
        XCTAssertEqual(macBook.meant, "MacBook")
        let api = try Prefilter.candidate(hunk("a p i", "API"), knownKeys: [], deniedKeys: []).get()
        XCTAssertEqual(api.meant, "API")
    }

    func testLongSidesAreDropped() {
        XCTAssertEqual(
            Prefilter.candidate(hunk("a b c d e", "x"), knownKeys: [], deniedKeys: []),
            .failure(.tooLong)
        )
        XCTAssertEqual(
            Prefilter.candidate(hunk("x", "a b c d e"), knownKeys: [], deniedKeys: []),
            .failure(.tooLong)
        )
    }

    func testFillersAndFunctionWordsAreDropped() {
        XCTAssertEqual(
            Prefilter.candidate(hunk("so", "um"), knownKeys: [], deniedKeys: []),
            .failure(.filler)
        )
        XCTAssertEqual(
            Prefilter.candidate(hunk("went", "and then the"), knownKeys: [], deniedKeys: []),
            .failure(.functionWords)
        )
        XCTAssertNoThrow(try Prefilter.candidate(hunk("went to", "walked to"), knownKeys: [], deniedKeys: []).get())
    }

    func testKnownAndDeniedWordsAreDropped() {
        let known = Prefilter.keys(["ChargeBee"])
        let denied = Prefilter.keys(["Bifrost"])
        XCTAssertEqual(
            Prefilter.candidate(hunk("Charge B", "chargebee"), knownKeys: known, deniedKeys: []),
            .failure(.alreadyKnown)
        )
        XCTAssertEqual(
            Prefilter.candidate(hunk("by frost", "Bifrost"), knownKeys: [], deniedKeys: denied),
            .failure(.denied)
        )
    }

    func testKeysJoinMultiwordEntries() {
        XCTAssertEqual(Prefilter.keys(["MacBook Pro", " "]), ["macbookpro"])
    }
}

// MARK: - wordlist.rs

final class WordListTests: XCTestCase {
    private func list() -> WordList {
        WordList(words: ["cluster", "notification", "Stage", "deploy", "fly", "move"])
    }

    func testListedWordsAreNotCoined() {
        XCTAssertFalse(list().isCoined("cluster"))
        XCTAssertFalse(list().isCoined("Notification"))
        XCTAssertFalse(list().isCoined("stage"))
    }

    func testInflectionsOfListedWordsAreNotCoined() {
        XCTAssertFalse(list().isCoined("clusters"))
        XCTAssertFalse(list().isCoined("deployed"))
        XCTAssertFalse(list().isCoined("deploying"))
        XCTAssertFalse(list().isCoined("flies"))
        XCTAssertFalse(list().isCoined("moved"))
        XCTAssertFalse(list().isCoined("moving"))
        XCTAssertFalse(list().isCoined("cluster's"))
    }

    func testUnknownAlphabeticWordsAreCoined() {
        XCTAssertTrue(list().isCoined("Zentryx"))
        XCTAssertTrue(list().isCoined("kavuu"))
    }

    func testShortOrNonAlphabeticTermsAreNeverCoined() {
        XCTAssertFalse(list().isCoined("ab"))
        XCTAssertFalse(list().isCoined("K8s"))
        XCTAssertFalse(list().isCoined("CI/CD"))
        XCTAssertFalse(list().isCoined("two words"))
    }

    func testEmptyListJudgesNothingCoined() {
        XCTAssertFalse(WordList(words: [String]()).isCoined("Zentryx"))
    }
}

// MARK: - check.rs

final class CheckTests: XCTestCase {
    func testOnlyNameLikeKindsAreVocabulary() {
        for kind in [CorrectionKind.personName, .productOrCompany, .projectOrService, .acronym, .technicalTerm] {
            XCTAssertTrue(kind.isVocabulary, "\(kind)")
        }
        for kind in [CorrectionKind.commonWord, .rewording, .grammar, .formatting] {
            XCTAssertFalse(kind.isVocabulary, "\(kind)")
        }
    }

    func testKindsRoundTripAsCamelCase() throws {
        let decoder = JSONDecoder()
        let kind = try decoder.decode(CorrectionKind.self, from: Data("\"productOrCompany\"".utf8))
        XCTAssertEqual(kind, .productOrCompany)
        XCTAssertThrowsError(try decoder.decode(CorrectionKind.self, from: Data("\"ProductOrCompany\"".utf8)))
        let encoded = try JSONEncoder().encode(CorrectionKind.productOrCompany)
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), "\"productOrCompany\"")
    }

    func testUserPromptNumbersPairsWithContext() {
        let candidates = [Candidate(heard: "Charge B", meant: "ChargeBee")]
        XCTAssertEqual(
            Check.userPrompt(candidates, context: "We moved billing to ChargeBee."),
            "Pairs:\n1. heard: \"Charge B\" — meant: \"ChargeBee\"\n   sentence: \"We moved billing to ChargeBee.\"\n"
        )
    }

    func testAlignRejectsAMismatchedVerdictCount() throws {
        XCTAssertEqual(try Check.align([.acronym, .grammar], expected: 2), [.acronym, .grammar])
        XCTAssertThrowsError(try Check.align([.acronym], expected: 2)) { error in
            XCTAssertEqual(
                error as? VocabularyCheckError,
                .verdictCountMismatch(returned: 1, expected: 2)
            )
        }
    }

    /// Talks to the on-device model. Run by hand on a Mac with Apple
    /// Intelligence: `HANDY_LIVE_MODEL=1 swift test --filter appleIntelligenceClassifiesRealPairs`.
    func testAppleIntelligenceClassifiesRealPairs() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["HANDY_LIVE_MODEL"] != nil,
            "set HANDY_LIVE_MODEL=1 to talk to the on-device model"
        )
        let candidates = [
            Candidate(heard: "Charge B", meant: "ChargeBee"),
            Candidate(heard: "went to", meant: "walked to"),
            Candidate(heard: "s d k", meant: "SDK"),
            Candidate(heard: "form", meant: "from"),
        ]
        let kinds = try await AppleIntelligenceCheck().check(
            candidates,
            context: "We moved billing to ChargeBee and walked to the SDK from here."
        )
        print(kinds)
        XCTAssertEqual(kinds.count, 4)
        XCTAssertTrue(kinds[0].isVocabulary)
        XCTAssertFalse(kinds[1].isVocabulary)
        XCTAssertTrue(kinds[2].isVocabulary)
        XCTAssertFalse(kinds[3].isVocabulary)
    }
}

// MARK: - readback.rs (pure text functions)

final class ReadBackTextTests: XCTestCase {
    func testPlaceholderAfterSendCountsAsWholesaleReplacement() {
        XCTAssertTrue(ReadBackText.replacedWholesale(
            previous: "Zentryx is the new staging cluster",
            next: "Type / for commands"
        ))
        XCTAssertTrue(ReadBackText.replacedWholesale(
            previous: "Zentryx is the new staging cluster",
            next: ""
        ))
    }

    func testEditsThatKeepAnyWordAreNotWholesale() {
        XCTAssertFalse(ReadBackText.replacedWholesale(
            previous: "Zentrix is the new staging cluster",
            next: "Zentryx is the new staging cluster"
        ))
        XCTAssertFalse(ReadBackText.replacedWholesale(previous: "cluster", next: "Cluster."))
    }

    func testNothingReplacesAnEmptyPreviousValue() {
        XCTAssertFalse(ReadBackText.replacedWholesale(previous: "", next: "Type / for commands"))
    }

    func testSnapshotAnchorsAroundThePasteAtTheCaret() throws {
        let value = "Intro. We moved billing to Charge B last week. Outro."
        let pasted = "We moved billing to Charge B last week."
        let caret = "Intro. We moved billing to Charge B last week.".utf16.count
        let snap = try XCTUnwrap(ReadBackText.snapshot(value: value, pasted: pasted, caretUTF16: caret))
        XCTAssertEqual(snap.prefix, "Intro. ")
        XCTAssertEqual(snap.pasted, pasted)
        XCTAssertEqual(snap.suffix, " Outro.")
    }

    func testSnapshotPrefersTheOccurrenceEndingAtTheCaret() throws {
        let value = "hello hello hello"
        let caret = "hello hello".utf16.count
        let atCaret = try XCTUnwrap(ReadBackText.snapshot(value: value, pasted: "hello", caretUTF16: caret))
        XCTAssertEqual(atCaret.prefix, "hello ")
        XCTAssertEqual(atCaret.suffix, " hello")
        let last = try XCTUnwrap(ReadBackText.snapshot(value: value, pasted: "hello", caretUTF16: nil))
        XCTAssertEqual(last.prefix, "hello hello ")
    }

    func testSnapshotToleratesATrailingSpaceThatDidNotLand() throws {
        let snap = try XCTUnwrap(ReadBackText.snapshot(value: "Say ChargeBee", pasted: "Say ChargeBee ", caretUTF16: nil))
        XCTAssertEqual(snap.pasted, "Say ChargeBee")
        XCTAssertNil(ReadBackText.snapshot(value: "nothing here", pasted: "absent", caretUTF16: nil))
    }

    func testSnapshotHandlesMultibyteTextBeforeTheCaret() throws {
        let value = "Résumé — naïve café: Charge B now"
        let caret = value.utf16.count
        let snap = try XCTUnwrap(ReadBackText.snapshot(value: value, pasted: "Charge B now", caretUTF16: caret))
        XCTAssertEqual(snap.prefix, "Résumé — naïve café: ")
    }

    func testCurrentSpanFollowsEditsInsideTheAnchorsOnly() throws {
        let snap = try XCTUnwrap(ReadBackText.snapshot(value: "A. Charge B here. Z.", pasted: "Charge B here.", caretUTF16: nil))
        XCTAssertEqual(ReadBackText.currentSpan(of: "A. ChargeBee here. Z.", snapshot: snap), "ChargeBee here.")
        XCTAssertNil(ReadBackText.currentSpan(of: "A. ChargeBee here. Z. More typed.", snapshot: snap))
        XCTAssertNil(ReadBackText.currentSpan(of: "Changed. ChargeBee here. Z.", snapshot: snap))
        XCTAssertEqual(ReadBackText.currentSpan(of: "A.  Z.", snapshot: snap), "")
        XCTAssertNil(ReadBackText.currentSpan(of: "A. Z.", snapshot: snap))
    }

    func testCurrentSpanWithAnEmptySuffixIncludesTextTypedAfter() throws {
        let snap = try XCTUnwrap(ReadBackText.snapshot(value: "A. Charge B here.", pasted: "Charge B here.", caretUTF16: nil))
        XCTAssertEqual(
            ReadBackText.currentSpan(of: "A. ChargeBee here. And more.", snapshot: snap),
            "ChargeBee here. And more."
        )
    }

    func testTimingConstantsMatchTheRustSession() {
        XCTAssertEqual(ReadBackText.maxFieldBytes, 200_000)
        XCTAssertEqual(ReadBackTiming.settle, .milliseconds(400))
        XCTAssertEqual(ReadBackTiming.captureAttempts, 8)
        XCTAssertEqual(ReadBackTiming.captureRetry, .milliseconds(300))
        XCTAssertEqual(ReadBackTiming.poll, .milliseconds(250))
        XCTAssertEqual(ReadBackTiming.limit, .seconds(90))
        XCTAssertEqual(ToastTiming.timeout, .seconds(8))
        XCTAssertEqual(ToastTiming.safetyHide, .seconds(60))
        XCTAssertEqual(ToastTiming.undoneLinger, .milliseconds(900))
    }
}
