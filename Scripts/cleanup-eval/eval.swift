import Foundation
import FoundationModels

/// Runs the cases in cases.json through the app's own path: PostProcessor
/// (prompt, guided generation, rewrite and opening guards), with the raw
/// transcript as the fallback when the model's output is rejected. The sources
/// are compiled in by run.sh, so this scores exactly what ships. A case passes
/// when the output matches the expected text, or any entry in `alsoAccepted`,
/// each of which says why it counts. Case and punctuation are ignored.
struct Variant: Decodable { let text: String; let why: String }

struct Case: Decodable {
    let input: String
    /// The cleaned text wanted; `alsoAccepted` lists other outputs that count, each with why.
    let expected: String
    let alsoAccepted: [Variant]
    /// The user's custom words, as they would be at the time; empty when the case has none.
    let customWords: [String]
    var accepted: [String] { [expected] + alsoAccepted.map(\.text) }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        input = try c.decode(String.self, forKey: .input)
        expected = try c.decode(String.self, forKey: .expected)
        alsoAccepted = try c.decodeIfPresent([Variant].self, forKey: .alsoAccepted) ?? []
        customWords = try c.decodeIfPresent([String].self, forKey: .customWords) ?? []
    }
    enum CodingKeys: CodingKey { case input, expected, alsoAccepted, customWords }
}

@main struct Eval {
    static func normalise(_ s: String) -> String {
        s.lowercased().split { !$0.isLetter && !$0.isNumber && !"$£€%".contains($0) }.joined(separator: " ")
    }

    static func main() async throws {
        let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: dir.appendingPathComponent("cases.json")))
        guard case .available = PostProcessor.availability else { print("Apple Intelligence is not available on this Mac"); exit(2) }
        var failed = 0
        for c in cases {
            let out = await PostProcessor.shared.run(c.input, customWords: c.customWords) ?? c.input
            let ok = c.accepted.contains { normalise(out) == normalise($0) }
            if !ok { failed += 1 }
            print("\(ok ? "PASS" : "FAIL")  \(c.input)")
            if !ok { print("      expected: \(c.accepted.joined(separator: "\n             or: "))\n      got:      \(out)") }
        }
        print("\n\(cases.count - failed)/\(cases.count) passed")
        exit(failed == 0 ? 0 : 1)
    }
}
