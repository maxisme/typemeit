import Foundation

struct Case: Decodable {
    let input: String
    let expected: [String]
    init(input: String, expected: [String]) { self.input = input; self.expected = expected }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        input = try c.decode(String.self, forKey: .input)
        if let list = try? c.decode([String].self, forKey: .expected) { expected = list } else { expected = [try c.decode(String.self, forKey: .expected)] }
    }
    enum CodingKeys: CodingKey { case input, expected }
}

enum Cases {
    static let instructions = "You clean up speech-to-text transcripts. Return only the cleaned transcript text."

    /// The formatting rule under test for long dictations. Not in the app's prompt.
    static let formattingRule = """
    8. Format speech that has a structure. When the speaker counts off several items (first, second, third; one, two, three), keep the lead-in sentence and end it with a colon, then put each item on its own line as a numbered list ("1. ", "2. ", "3. "), keeping every word of the item and dropping only the counting word. Start a new paragraph after a blank line where the topic changes. A single sentence or a short message stays on one line. Do not add headings, bold text or any content.

    """

    /// Long dictations with the layouts that count as right. Compared line by
    /// line after normalising, so the list shape has to match as well as the words.
    static let long = [
        Case(input: "okay so three things for tomorrow first we need to finish the landing page second um call the accountant about the vat return and third book the train tickets for friday also separately i was thinking about the pricing page maybe we drop the free tier and just have a two week trial instead what do you think",
             expected: [
                """
                Okay so three things for tomorrow:
                1. We need to finish the landing page
                2. Call the accountant about the VAT return.
                3. Book the train tickets for Friday.

                Also separately, I was thinking about the pricing page. Maybe we drop the free tier and just have a two-week trial instead. What do you think?
                """,
                """
                Okay, so three things for tomorrow:
                1. Finish the landing page.
                2. Call the accountant about the VAT return.
                3. Book the train tickets for Friday.

                Also, I was thinking about the pricing page. Maybe we drop the free tier and just have a two-week trial instead. What do you think?
                """,
             ]),
        Case(input: "hi sarah thanks for sending over the draft i had a read through last night and overall i think its in good shape a couple of things though the intro is quite long and i think we lose people before we get to the point maybe cut it to two sentences and the section on pricing needs the new numbers from finance i'll send those over this afternoon anyway let me know if you want to jump on a call to go through it",
             expected: [
                """
                Hi Sarah, thanks for sending over the draft. I had a read through last night and overall I think it's in good shape.

                A couple of things though. The intro is quite long and I think we lose people before we get to the point. Maybe cut it to two sentences. And the section on pricing needs the new numbers from finance. I'll send those over this afternoon.

                Anyway, let me know if you want to jump on a call to go through it.
                """,
                """
                Hi Sarah, thanks for sending over the draft. I had a read through last night and overall I think it's in good shape. A couple of things though. The intro is quite long and I think we lose people before we get to the point. Maybe cut it to two sentences. And the section on pricing needs the new numbers from finance. I'll send those over this afternoon. Anyway, let me know if you want to jump on a call to go through it.
                """,
             ]),
        Case(input: "right so notes from the call with the supplier they can do the first batch by the twelfth but only five hundred units the full order of two thousand would be end of month pricing is unchanged at four pounds fifty a unit if we pay upfront otherwise four eighty um they also asked about the packaging change we mentioned last time i said we'd come back to them by wednesday oh and one more thing the contact there is now priya not dan dan has moved to the sales team",
             expected: [
                """
                Right so notes from the call with the supplier. They can do the first batch by the 12th but only 500 units. The full order of 2000 would be end of month. Pricing is unchanged at £4.50 a unit if we pay upfront, otherwise £4.80. They also asked about the packaging change we mentioned last time. I said we'd come back to them by Wednesday.

                Oh and one more thing, the contact there is now Priya not Dan. Dan has moved to the sales team.
                """,
             ]),
    ]

    /// Non-empty lines compared one by one, each with case and punctuation ignored.
    /// Blank lines are dropped, so paragraph spacing is free but list lines must match.
    static func normaliseLayout(_ s: String) -> [String] {
        s.split(separator: "\n").map { normalise(String($0)) }.filter { !$0.isEmpty }
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

    static func withFormatting(_ template: String) -> String {
        template.replacingOccurrences(of: "\nPreserve the meaning", with: formattingRule + "\nPreserve the meaning")
    }

    static func load(repoRoot: URL) throws -> [Case] {
        try JSONDecoder().decode([Case].self, from: Data(contentsOf: repoRoot.appendingPathComponent("Scripts/cleanup-eval/cases.json")))
    }
}
