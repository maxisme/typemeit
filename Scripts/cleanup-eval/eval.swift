import Foundation
import FoundationModels

/// Runs the cases in cases.json through the on-device model with the prompt
/// template pulled from PostProcessor.swift, and prints each result against
/// the expected text. `expected` is one string or a list of acceptable ones, for
/// wordings that are all fine. The comparison ignores case and punctuation so a
/// comma for a full stop does not fail a case; word changes do. An optional
/// argument names another PostProcessor.swift to read the template from.
@Generable struct CleanedTranscript: Sendable { let cleanedText: String }

struct Case: Decodable {
    let input: String
    let expected: [String]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        input = try c.decode(String.self, forKey: .input)
        if let list = try? c.decode([String].self, forKey: .expected) { expected = list } else { expected = [try c.decode(String.self, forKey: .expected)] }
    }
    enum CodingKeys: CodingKey { case input, expected }
}

@main struct Eval {
    static func normalise(_ s: String) -> String {
        s.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "$" && $0 != "£" && $0 != "€" && $0 != "%" }.joined(separator: " ")
    }

    static func template(from source: String) -> String {
        let start = source.range(of: "static let template = \"\"\"\n")!.upperBound
        let end = source.range(of: "\n    \"\"\"", range: start..<source.endIndex)!.lowerBound
        return source[start..<end].split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.hasPrefix("    ") ? String($0.dropFirst(4)) : String($0) }.joined(separator: "\n")
    }

    static func main() async throws {
        let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let root = dir.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1]) : root.appendingPathComponent("TypeMeIt/PostProcessor.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let tpl = template(from: source)
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: dir.appendingPathComponent("cases.json")))
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        guard case .available = model.availability else { print("Apple Intelligence is not available on this Mac"); exit(2) }
        var failed = 0
        for c in cases {
            let session = LanguageModelSession(model: model, instructions: "You clean up speech-to-text transcripts. Return only the cleaned transcript text.")
            let r = try await session.respond(to: tpl.replacingOccurrences(of: "${output}", with: c.input), generating: CleanedTranscript.self, options: GenerationOptions(sampling: .greedy))
            let out = r.content.cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
            let ok = c.expected.contains { normalise(out) == normalise($0) }
            if !ok { failed += 1 }
            print("\(ok ? "PASS" : "FAIL")  \(c.input)")
            if !ok { print("      expected: \(c.expected.joined(separator: "\n             or: "))\n      got:      \(out)") }
        }
        print("\n\(cases.count - failed)/\(cases.count) passed")
        exit(failed == 0 ? 0 : 1)
    }
}
