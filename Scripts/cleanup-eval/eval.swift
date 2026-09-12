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
/// rules in the instructions, then WritingStyle.apply on the output; a case
/// with `matrix` runs under every combination of styles; a case with `wish`
/// is reported but never fails the run. A case passes
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
    /// Run under every combination of writing styles except lowercase, which
    /// is pure code and covered by unit tests. `expected` and `alsoAccepted`
    /// are then templates: `{digits:one|1}` reads "one" with digits off and
    /// "1" with it on. Case and punctuation are compared when the output or
    /// expected text has a line break.
    let matrix: Bool
    /// Wanted but not passing on today's model: run and reported, never
    /// counted as a failure. The list to re-check when a new model lands.
    let wish: Bool
    var accepted: [String] { [expected] + alsoAccepted.map(\.text) }
    var whys: [String] { alsoAccepted.map(\.why) }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        input = try c.decode(String.self, forKey: .input)
        screen = try c.decodeIfPresent([String].self, forKey: .screen)
        expected = try c.decode(String.self, forKey: .expected)
        alsoAccepted = try c.decodeIfPresent([Variant].self, forKey: .alsoAccepted) ?? []
        customWords = try c.decodeIfPresent([String].self, forKey: .customWords) ?? []
        styles = Set(try c.decodeIfPresent([WritingStyle].self, forKey: .styles) ?? [])
        exact = try c.decodeIfPresent(Bool.self, forKey: .exact) ?? false
        matrix = try c.decodeIfPresent(Bool.self, forKey: .matrix) ?? false
        wish = try c.decodeIfPresent(Bool.self, forKey: .wish) ?? false
    }
    enum CodingKeys: CodingKey { case input, screen, expected, alsoAccepted, customWords, styles, exact, matrix, wish }

    /// The runs this case stands for: itself, or one per style combination.
    var runs: [Run] {
        guard matrix else { return [Run(input: input, styles: styles, accepted: accepted, whys: whys, exact: exact)] }
        let all = WritingStyle.allCases.filter { $0 != .lowercase }
        return (0..<(1 << all.count)).map { bits in
            let on = Set(all.enumerated().filter { bits & (1 << $0.offset) != 0 }.map(\.element))
            return Run(input: input, styles: on, accepted: accepted.map { Case.expand($0, on) }, whys: whys, exact: exact)
        }
    }

    /// Innermost slots first, so a slot may hold other slots.
    static let slot = try! NSRegularExpression(pattern: #"\{(\w+):([^{}|]*)\|([^{}]*)\}"#)
    static func expand(_ template: String, _ on: Set<WritingStyle>) -> String {
        var out = template
        while let m = slot.firstMatch(in: out, range: NSRange(location: 0, length: (out as NSString).length)) {
            let ns = out as NSString
            guard let style = WritingStyle(rawValue: ns.substring(with: m.range(at: 1))) else { fatalError("unknown style in template: \(template)") }
            let pick = ns.substring(with: m.range(at: on.contains(style) ? 3 : 2))
            out = ns.replacingCharacters(in: m.range, with: pick)
        }
        return out.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([.?!,])"#, with: "$1", options: .regularExpression)
    }
}

struct Run {
    let input: String
    let styles: Set<WritingStyle>
    let accepted: [String]
    /// Why each `accepted` entry after the first counts.
    let whys: [String]
    let exact: Bool
    /// Line breaks always count, so a list is only right when it is one;
    /// within a line, case and punctuation are ignored as usual. Returns the
    /// index of the accepted text that matched.
    func match(_ out: String) -> Int? {
        if exact { return accepted.firstIndex { Eval.tidy(out) == Eval.tidy($0) } }
        return accepted.firstIndex { Eval.normaliseLines(out) == Eval.normaliseLines($0) }
    }
}

/// One entry of result.json per case, for anything that renders the run.
struct Result: Encodable {
    let input, output: String
    let styles: [String]
    let pass: Bool
    let wish: Bool
    /// Which accepted text matched: 0 is `expected`, 1 the first `alsoAccepted`.
    let matched: Int?
    let expected: [String]
    let whys: [String]
    let screen: [String]?
    let terms: [String]
    let withoutScreen: String?
    let withoutScreenPass: Bool?
}

@main struct Eval {
    /// evals.md: every run grouped by its styles, with what the model was
    /// told from the screen and what came back.
    static func markdown(_ results: [Result], passed: Int, total: Int, granted: Int, wished: Int) -> String {
        func cell(_ s: String) -> String { s.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: "<br>") }
        var out = "# Clean-up evals\n\nGenerated by `make eval`. \(passed)/\(total) passed"
        out += wished > 0 ? ", wish list \(granted)/\(wished) granted.\n" : ".\n"
        var groups: [(String, [Result])] = []
        for r in results.filter({ !$0.wish }) + results.filter(\.wish) {
            var key = r.styles.isEmpty ? (r.screen == nil ? "no styles" : "screen") : r.styles.joined(separator: ", ")
            if r.wish { key = "wish list: " + key }
            if let i = groups.firstIndex(where: { $0.0 == key }) { groups[i].1.append(r) } else { groups.append((key, [r])) }
        }
        for (key, rs) in groups {
            let screen = rs.contains { $0.screen != nil }
            out += "\n## \(key) (\(rs.count))\n\n| | input | expected |\(screen ? " screen terms |" : "") got |\n|---|---|---|\(screen ? "---|" : "")---|\n"
            for r in rs {
                var expected = cell(r.expected[0])
                for (alt, why) in zip(r.expected.dropFirst(), r.whys) { expected += "<br>— or, \(cell(why)) —<br>" + cell(alt) }
                var got = cell(r.output)
                if let b = r.withoutScreen, b != r.output { got += "<br>*without screen:* " + cell(b) }
                let mark = r.wish ? (r.pass ? "granted" : "not yet") : (r.pass ? "pass" : "**fail**")
                let terms = screen ? " \(cell(r.terms.joined(separator: ", "))) |" : ""
                out += "| \(mark) | \(cell(r.input)) | \(expected) |\(terms) \(got) |\n"
            }
        }
        return out
    }

    /// Whitespace runs collapsed within a line, curly quotes straightened, a
    /// trailing full stop dropped as the pipeline drops it; everything else kept.
    static func tidy(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "‘", with: "'")
            .split(separator: "\n").map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }.joined(separator: "\n")
        if t.hasSuffix(".") { t.removeLast() }
        return t
    }

    static func normaliseLines(_ s: String) -> String {
        s.split(separator: "\n", omittingEmptySubsequences: false).map { normalise(String($0)) }.joined(separator: "\n")
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
        var total = 0
        var wished = 0, granted = 0
        for c in cases {
            let terms = await MainActor.run { ScreenContext.terms(from: c.screen ?? [], excluding: c.customWords) }
            for r in c.runs {
                total += 1
                let out = WritingStyle.apply(r.styles, to: await PostProcessor.shared.run(r.input, customWords: c.customWords, screenTerms: terms, styles: r.styles) ?? r.input)
                let matched = r.match(out)
                let ok = matched != nil
                if c.wish { wished += 1; if ok { granted += 1 } } else if !ok { failed += 1 }
                if c.wish { total -= 1 }
                let tag = r.styles.isEmpty ? (c.matrix ? "  [none]" : "") : "  [\(r.styles.map(\.rawValue).sorted().joined(separator: ", "))]"
                print("\(c.wish ? (ok ? "WISH  granted" : "WISH  not yet") : (ok ? "PASS" : "FAIL"))  \(r.input)\(tag)")
                if !ok { print("      expected: \(r.accepted.joined(separator: "\n             or: "))\n      got:      \(out)") }
                var blind: String?, blindOk: Bool?
                if c.screen != nil {
                    screened += 1
                    let b = await PostProcessor.shared.run(r.input, customWords: c.customWords) ?? r.input
                    let bOk = r.match(b) != nil
                    if ok, !bOk { helped += 1 }
                    if !ok, bOk { hurt += 1 }
                    print("      screen terms: \(terms.joined(separator: ", "))")
                    if b != out { print("      without screen: \(b)") }
                    blind = b; blindOk = bOk
                }
                results.append(Result(input: r.input, output: out, styles: r.styles.map(\.rawValue).sorted(), pass: ok, wish: c.wish, matched: matched, expected: r.accepted, whys: r.whys, screen: c.screen, terms: terms, withoutScreen: blind, withoutScreenPass: blindOk))
            }
        }
        print("\n\(total - failed)/\(total) passed")
        if screened > 0 { print("screen: \(screened) cases, helped \(helped), hurt \(hurt)") }
        if wished > 0 { print("wish list: \(granted)/\(wished) granted") }
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try enc.encode(results).write(to: dir.appendingPathComponent("result.json"))
        try markdown(results, passed: total - failed, total: total, granted: granted, wished: wished).write(to: dir.appendingPathComponent("evals.md"), atomically: true, encoding: .utf8)
        exit(failed == 0 ? 0 : 1)
    }
}
