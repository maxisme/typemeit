import Foundation

struct Case: Decodable {
    let input: String
    /// The cleaned text wanted; `alsoAccepted` lists other outputs that count, each with why.
    let expected: [String]
    struct Variant: Decodable { let why: String; let text: String }
    init(input: String, expected: String, alsoAccepted: [Variant] = []) {
        self.input = input
        self.expected = [expected] + alsoAccepted.map(\.text)
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        input = try c.decode(String.self, forKey: .input)
        let also = try c.decodeIfPresent([Variant].self, forKey: .alsoAccepted) ?? []
        expected = [try c.decode(String.self, forKey: .expected)] + also.map(\.text)
    }
    enum CodingKeys: CodingKey { case input, expected, alsoAccepted }
}

enum Cases {
    /// The session instructions out of PostProcessor.swift.
    static func instructions(repoRoot: URL) throws -> String {
        let source = try String(contentsOf: repoRoot.appendingPathComponent("TypeMeIt/PostProcessor.swift"), encoding: .utf8)
        let start = source.range(of: "static let instructions = \"\"\"\n")!.upperBound
        let end = source.range(of: "\n    \"\"\"", range: start..<source.endIndex)!.lowerBound
        return source[start..<end].split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.hasPrefix("    ") ? String($0.dropFirst(4)) : String($0) }.joined(separator: "\n")
    }

    static func normalise(_ s: String) -> String {
        s.lowercased().split { !$0.isLetter && !$0.isNumber && !"$£€%".contains($0) }.joined(separator: " ")
    }

    /// The template out of PostProcessor.swift, so the benchmark always runs the app's live prompt.
    static func template(repoRoot: URL) throws -> String {
        let source = try String(contentsOf: repoRoot.appendingPathComponent("TypeMeIt/PostProcessor.swift"), encoding: .utf8)
        let start = source.range(of: "static let template = \"\"\"\n")!.upperBound
        let end = source.range(of: "\n    \"\"\"", range: start..<source.endIndex)!.lowerBound
        return source[start..<end].split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.hasPrefix("    ") ? String($0.dropFirst(4)) : String($0) }.joined(separator: "\n")
    }

    static func load(repoRoot: URL) throws -> [Case] {
        try JSONDecoder().decode([Case].self, from: Data(contentsOf: repoRoot.appendingPathComponent("Scripts/cleanup-eval/cases.json")))
    }
}
