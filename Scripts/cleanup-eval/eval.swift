import Foundation
import FoundationModels

/// Runs the cases in cases.json through the app's own path, PostProcessor.clean:
/// the code passes before the model, the prompt, guided generation, the
/// rewrite and opening guards, the raw transcript as the fallback when the
/// model's output is rejected, then the writing styles. The sources
/// are compiled in by run.sh, so this scores exactly what ships. A case with
/// `screen`, lines of text standing in for the window the user dictates into,
/// goes through ScreenContext's term filter first and the model is told the
/// terms, the way the read-the-screen setting does; it is also run without
/// them so the summary says whether the screen helped. A case with `styles`
/// runs with those writing styles on, the way the writing-style rows do: the
/// rules in the instructions and the code passes on the output; a case
/// with `matrix` runs under every combination of styles; a case with `wish`
/// is reported but never fails the run; a normal case has one expected text
/// and only alternatives that are as good. A case passes
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
    /// Wanted but not passing on today's model: what should happen and why
    /// it does not yet. Run and reported, never counted as a failure; the
    /// list to re-check when a new model lands.
    let wish: String?
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
        wish = try c.decodeIfPresent(String.self, forKey: .wish)
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
    let wish: String?
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
    /// evals.html: every run grouped by its styles, with what the model was
    /// told from the screen and what came back.
    static func html(_ results: [Result], passed: Int, total: Int, granted: Int, wished: Int) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        var out = """
        <!doctype html><meta charset="utf-8"><title>Clean-up evals</title>
        <style>
        body{font:14px/1.45 -apple-system,system-ui,sans-serif;margin:24px;color:#222}
        table{border-collapse:collapse;width:100%;margin-bottom:32px}
        th,td{border:1px solid #ddd;padding:6px 10px;vertical-align:top;text-align:left}
        th{background:#f4f4f4;font-weight:600}
        td.mark{white-space:nowrap;width:1%}
        .fail td.mark{color:#b00020;font-weight:600}
        .alt{border-top:1px dashed #bbb;margin-top:6px;padding-top:6px}
        .why{color:#666;font-size:12px;margin-bottom:2px}
        .text{white-space:pre-wrap}
        .terms{color:#444;font-size:12px}
        tr.divider td{background:#fff8e1;color:#664;font-size:12px}
        tr.wish td{background:#fffdf5}
        </style>
        <h1>Clean-up evals</h1>
        <p>Generated by <code>make eval</code>. \(passed)/\(total) passed\(wished > 0 ? ", wish list \(granted)/\(wished) granted" : "").</p>

        """
        var groups: [(String, [Result])] = []
        for r in results.filter({ $0.wish == nil }) + results.filter({ $0.wish != nil }) {
            let key = r.styles.isEmpty ? (r.screen == nil ? "no styles" : "screen") : r.styles.joined(separator: ", ")
            if let i = groups.firstIndex(where: { $0.0 == key }) { groups[i].1.append(r) } else { groups.append((key, [r])) }
        }
        for (key, rs) in groups {
            let screen = rs.contains { $0.screen != nil }
            let columns = screen ? 5 : 4
            out += "<h2>\(esc(key)) (\(rs.filter { $0.wish == nil }.count))</h2>\n<table><tr><th></th><th>input</th><th>expected</th>\(screen ? "<th>screen terms</th>" : "")<th>got</th></tr>\n"
            var inWishes = false
            for r in rs {
                if r.wish != nil, !inWishes {
                    inWishes = true
                    out += "<tr class=\"divider\"><td colspan=\"\(columns)\">not yet</td></tr>\n"
                }
                let mark = r.wish != nil ? (r.pass ? "granted" : "not yet") : (r.pass ? "pass" : "fail")
                var expected = "<div class=\"text\">\(esc(r.expected[0]))</div>"
                if let wish = r.wish { expected += "<div class=\"why\">\(esc(wish))</div>" }
                for (alt, why) in zip(r.expected.dropFirst(), r.whys) {
                    expected += "<div class=\"alt\"><div class=\"why\">or, \(esc(why))</div><div class=\"text\">\(esc(alt))</div></div>"
                }
                var got = "<div class=\"text\">\(esc(r.output))</div>"
                if let b = r.withoutScreen, b != r.output { got += "<div class=\"alt\"><div class=\"why\">without the screen</div><div class=\"text\">\(esc(b))</div></div>" }
                let terms = screen ? "<td class=\"terms\">\(esc(r.terms.joined(separator: ", ")))</td>" : ""
                out += "<tr class=\"\(r.wish != nil ? "wish" : r.pass ? "pass" : "fail")\"><td class=\"mark\">\(mark)</td><td>\(esc(r.input))</td><td>\(expected)</td>\(terms)<td>\(got)</td></tr>\n"
            }
            out += "</table>\n"
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
        s.lowercased().split { !$0.isLetter && !$0.isNumber && !"$£€%\"".contains($0) }.joined(separator: " ")
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
                let out = await PostProcessor.shared.clean(r.input, customWords: c.customWords, screenTerms: terms, styles: r.styles).text
                let matched = r.match(out)
                let ok = matched != nil
                if c.wish != nil { wished += 1; total -= 1; if ok { granted += 1 } } else if !ok { failed += 1 }
                let tag = r.styles.isEmpty ? (c.matrix ? "  [none]" : "") : "  [\(r.styles.map(\.rawValue).sorted().joined(separator: ", "))]"
                print("\(c.wish != nil ? (ok ? "WISH  granted" : "WISH  not yet") : (ok ? "PASS" : "FAIL"))  \(r.input)\(tag)")
                if !ok { print("      expected: \(r.accepted.joined(separator: "\n             or: "))\n      got:      \(out)") }
                var blind: String?, blindOk: Bool?
                if c.screen != nil {
                    screened += 1
                    let b = await PostProcessor.shared.clean(r.input, customWords: c.customWords, styles: r.styles).text
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
        try html(results, passed: total - failed, total: total, granted: granted, wished: wished).write(to: dir.appendingPathComponent("evals.html"), atomically: true, encoding: .utf8)
        exit(failed == 0 ? 0 : 1)
    }
}
