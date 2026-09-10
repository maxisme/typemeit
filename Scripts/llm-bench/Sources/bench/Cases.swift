import Foundation

struct Case: Decodable {
    let input: String
    /// Text on the window being dictated into, one line each, or nil for none.
    let screen: [String]?
    /// The cleaned text wanted; `alsoAccepted` lists other outputs that count, each with why.
    let expected: [String]
    struct Variant: Decodable { let why: String; let text: String }
    init(input: String, screen: [String]? = nil, expected: String, alsoAccepted: [Variant] = []) {
        self.input = input
        self.screen = screen
        self.expected = [expected] + alsoAccepted.map(\.text)
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        input = try c.decode(String.self, forKey: .input)
        screen = try c.decodeIfPresent([String].self, forKey: .screen)
        let also = try c.decodeIfPresent([Variant].self, forKey: .alsoAccepted) ?? []
        expected = [try c.decode(String.self, forKey: .expected)] + also.map(\.text)
    }
    enum CodingKeys: CodingKey { case input, screen, expected, alsoAccepted }
}

enum Cases {
    static func normalise(_ s: String) -> String {
        s.lowercased().split { !$0.isLetter && !$0.isNumber && !"$£€%".contains($0) }.joined(separator: " ")
    }

    static func load(repoRoot: URL) throws -> [Case] {
        try JSONDecoder().decode([Case].self, from: Data(contentsOf: repoRoot.appendingPathComponent("Scripts/cleanup-eval/cases.json")))
    }
}
