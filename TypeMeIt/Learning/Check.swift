// The vocabulary check: the one judgment rules are bad at, made by the
// on-device model. Apple Intelligence answers through guided generation and
// returns a kind per pair; yes or no is derived from the kind in code,
// because asking the model for a boolean directly made it say yes to almost
// every rewording.

import Foundation
import FoundationModels

/// What the model says the corrected text is.
enum CorrectionKind: String, Sendable, Codable, CaseIterable {
    case personName
    case productOrCompany
    case projectOrService
    case acronym
    case technicalTerm
    case commonWord
    case rewording
    case grammar
    case formatting

    var isVocabulary: Bool {
        switch self {
        case .personName, .productOrCompany, .projectOrService, .acronym, .technicalTerm:
            true
        case .commonWord, .rewording, .grammar, .formatting:
            false
        }
    }
}

/// One verdict per candidate, in candidate order.
protocol VocabularyCheck: Sendable {
    func check(_ candidates: [Candidate], context: String) async throws -> [CorrectionKind]
}

enum VocabularyCheckError: Error, Equatable, Sendable {
    /// Apple Intelligence is not available on this device right now.
    case modelUnavailable
    /// The model returned a kind that is not a `CorrectionKind`.
    case unknownKind(String)
    /// The model returned a different number of verdicts than pairs.
    case verdictCountMismatch(returned: Int, expected: Int)
}

enum Check {
    /// Instructions given to the model. Measured on Apple Intelligence at 1.00
    /// precision and 0.88 recall over 62 labelled pairs with greedy decoding.
    static let instructions = """
        You classify corrections a person made to text written by a speech-to-text model. Each numbered pair gives what the model wrote ("heard"), what the person changed it to ("meant"), and the sentence it appeared in.

        Look at "meant" and decide what kind of thing it is:
        - personName: a person's name.
        - productOrCompany: a product, brand, company or tool name, including compound names such as MacBook, GitHub or ChatGPT.
        - projectOrService: an internal project, service, environment or codename.
        - acronym: an acronym or initialism such as SDK, GDPR, R&D, SQL or CI/CD.
        - technicalTerm: a specialist term from software, engineering, science, medicine, law or finance that a general dictionary would mark as jargon, such as webhook, monorepo, mutex, backfill, idempotent or cache.
        - commonWord: an ordinary English word or phrase that a general dictionary lists as everyday language, even when "heard" was nonsense and even when the sentence is technical. Examples: source, from, there, obtain, believe, huge, assist.
        - rewording: "meant" says the same thing as "heard" in different words.
        - grammar: a change of tense, number, agreement, or the spelling of a common word.
        - formatting: numbers, currency, percentages or punctuation.

        The test for commonWord against technicalTerm: would a non-technical adult recognise "meant" as an everyday word? If yes, it is commonWord.

        Return exactly one verdict per pair, in the same order, copying "meant" exactly as given.
        """

    /// The numbered pairs the model is asked about, each with the edited
    /// sentence for context.
    static func userPrompt(_ candidates: [Candidate], context: String) -> String {
        var text = "Pairs:\n"
        for (index, candidate) in candidates.enumerated() {
            text += "\(index + 1). heard: \"\(candidate.heard)\" — meant: \"\(candidate.meant)\"\n   sentence: \"\(context)\"\n"
        }
        return text
    }

    /// The verdicts when there is exactly one per pair; otherwise an error.
    static func align(_ kinds: [CorrectionKind], expected: Int) throws -> [CorrectionKind] {
        if kinds.count != expected {
            throw VocabularyCheckError.verdictCountMismatch(returned: kinds.count, expected: expected)
        }
        return kinds
    }
}

// MARK: - Apple Intelligence

@Generable
private enum GeneratedCorrectionKind: String, Sendable {
    case personName
    case productOrCompany
    case projectOrService
    case acronym
    case technicalTerm
    case commonWord
    case rewording
    case grammar
    case formatting
}

@Generable
private struct PairKindVerdict: Sendable {
    @Guide(description: "The corrected text, copied exactly as given in the pair")
    let meant: String
    @Guide(description: "The kind of thing the corrected text is, using the definitions in the instructions")
    let kind: GeneratedCorrectionKind
}

@Generable
private struct KindVerdictList: Sendable {
    @Guide(description: "Exactly one verdict per numbered pair, in the same order as the pairs")
    let verdicts: [PairKindVerdict]
}

/// The check answered by the on-device model through guided generation.
struct AppleIntelligenceCheck: VocabularyCheck {
    init() {}

    func check(_ candidates: [Candidate], context: String) async throws -> [CorrectionKind] {
        let model = SystemLanguageModel.default
        guard model.availability == .available else {
            throw VocabularyCheckError.modelUnavailable
        }
        let session = LanguageModelSession(model: model, instructions: Check.instructions)
        // Guided generation pins the output to one verdict per pair with a
        // kind drawn from the enum, so no free-text parsing is needed. Greedy
        // sampling is required: with the default sampling the same pair is
        // classified differently from one run to the next.
        let options = GenerationOptions(sampling: .greedy)
        let structured = try await session.respond(
            to: Check.userPrompt(candidates, context: context),
            generating: KindVerdictList.self,
            options: options
        )
        let kinds = try structured.content.verdicts.map { verdict in
            guard let kind = CorrectionKind(rawValue: verdict.kind.rawValue) else {
                throw VocabularyCheckError.unknownKind(verdict.kind.rawValue)
            }
            return kind
        }
        return try Check.align(kinds, expected: candidates.count)
    }
}
