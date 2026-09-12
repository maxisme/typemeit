import Foundation
import FoundationModels

/// Runs the cases in cases.json through the app's own path: PostProcessor
/// (prompt, guided generation, rewrite and opening guards), with the raw
/// transcript as the fallback when the model's output is rejected. The sources
/// are compiled in by run.sh, so this scores exactly what ships. A case with
/// `screen`, lines of text standing in for the window the user dictates into,
/// goes through ScreenContext's term filter first and the model is told the
/// terms, the way the read-the-screen setting does; it is also run without
/// them so the summary says whether the screen helped. A case with `styles`
/// runs with those writing styles on, the way the writing-style rows do: the
/// rules in the instructions, then WritingStyle.apply on the output. A case passes
/// when the output matches the expected text, or any entry in `alsoAccepted`,
/// each of which says why it counts. Case and punctuation are ignored unless
/// the case says `exact`.
struct Variant: Decodable { let text: String; let why: String }

struct Case: Decodable {
    let input: String
    /// Text on the window being dictated into, one line each, or nil for none.
    let screen: [String]?
    /// The cleaned text wanted; `alsoAccepted` lists other outputs that count, each with why.
    let expected: String
    let alsoAccepted: [Variant]
    /// The user's custom words, as they would be at the time; empty when the case has none.
    let customWords: [String]
    /// The writing styles turned on, by raw value; empty when the case has none.
    let styles: Set<WritingStyle>
    /// Compare case and punctuation too, for styles that are about those.
    let exact: Bool
    var accepted: [String] { [expected] + alsoAccepted.map(\.text) }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        input = try c.decode(String.self, forKey: .input)
        screen = try c.decodeIfPresent([String].self, forKey: .screen)
        expected = try c.decode(String.self, forKey: .expected)
        alsoAccepted = try c.decodeIfPresent([Variant].self, forKey: .alsoAccepted) ?? []
        customWords = try c.decodeIfPresent([String].self, forKey: .customWords) ?? []
        styles = Set(try c.decodeIfPresent([WritingStyle].self, forKey: .styles) ?? [])
        exact = try c.decodeIfPresent(Bool.self, forKey: .exact) ?? false
    }
    enum CodingKeys: CodingKey { case input, screen, expected, alsoAccepted, customWords, styles, exact }
    func matches(_ out: String) -> Bool {
        accepted.contains { exact ? Eval.tidy(out) == Eval.tidy($0) : Eval.normalise(out) == Eval.normalise($0) }
    }
}

/// One entry of result.json per case, for anything that renders the run.
struct Result: Encodable {
    let input, output: String
    let styles: [String]
    let pass: Bool
    let expected: [String]
    let screen: [String]?
    let terms: [String]
    let withoutScreen: String?
    let withoutScreenPass: Bool?
}

@main struct Eval {
    /// Whitespace runs collapsed within a line, curly quotes straightened, a
    /// trailing full stop dropped as the pipeline drops it; everything else kept.
    static func tidy(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "‘", with: "'")
            .split(separator: "\n").map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }.joined(separator: "\n")
        if t.hasSuffix(".") { t.removeLast() }
        return t
    }

    static func normalise(_ s: String) -> String {
        s.lowercased().split { !$0.isLetter && !$0.isNumber && !"$£€%".contains($0) }.joined(separator: " ")
    }

    static func main() async throws {
        let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: dir.appendingPathComponent("cases.json")))
        guard case .available = PostProcessor.availability else { print("Apple Intelligence is not available on this Mac"); exit(2) }
        var failed = 0
        var helped = 0, hurt = 0, screened = 0
        var results: [Result] = []
        for c in cases {
            let terms = await MainActor.run { ScreenContext.terms(from: c.screen ?? [], excluding: c.customWords) }
            let out = WritingStyle.apply(c.styles, to: await PostProcessor.shared.run(c.input, customWords: c.customWords, screenTerms: terms, styles: c.styles) ?? c.input)
            let ok = c.matches(out)
            if !ok { failed += 1 }
            let tag = c.styles.isEmpty ? "" : "  [\(c.styles.map(\.rawValue).sorted().joined(separator: ", "))]"
            print("\(ok ? "PASS" : "FAIL")  \(c.input)\(tag)")
            if !ok { print("      expected: \(c.accepted.joined(separator: "\n             or: "))\n      got:      \(out)") }
            var blind: String?, blindOk: Bool?
            if c.screen != nil {
                screened += 1
                let b = await PostProcessor.shared.run(c.input, customWords: c.customWords) ?? c.input
                let bOk = c.matches(b)
                if ok, !bOk { helped += 1 }
                if !ok, bOk { hurt += 1 }
                print("      screen terms: \(terms.joined(separator: ", "))")
                if b != out { print("      without screen: \(b)") }
                blind = b; blindOk = bOk
            }
            results.append(Result(input: c.input, output: out, styles: c.styles.map(\.rawValue).sorted(), pass: ok, expected: c.accepted, screen: c.screen, terms: terms, withoutScreen: blind, withoutScreenPass: blindOk))
        }
        print("\n\(cases.count - failed)/\(cases.count) passed")
        if screened > 0 { print("screen: \(screened) cases, helped \(helped), hurt \(hurt)") }
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try enc.encode(results).write(to: dir.appendingPathComponent("result.json"))
        exit(failed == 0 ? 0 : 1)
    }
}
