import Foundation

struct Case: Decodable { let input: String; let expected: String }

enum Cases {
    static let instructions = "You clean up speech-to-text transcripts. Return only the cleaned transcript text."

    /// The formatting rule under test for long dictations. Not in the app's prompt.
    static let formattingRule = """
    8. Format speech that has a structure. When the speaker lists several items (first, second, third; one, two, three; and then, and then), put each item on its own line beginning with "- ", keeping every word of the item and dropping only the counting word. Put a blank line between paragraphs where the topic changes. A single sentence or a short message stays on one line. Do not add headings, bold text or any content.

    """

    static let long = [
        "okay so three things for tomorrow first we need to finish the landing page second um call the accountant about the vat return and third book the train tickets for friday also separately i was thinking about the pricing page maybe we drop the free tier and just have a two week trial instead what do you think",
        "hi sarah thanks for sending over the draft i had a read through last night and overall i think its in good shape a couple of things though the intro is quite long and i think we lose people before we get to the point maybe cut it to two sentences and the section on pricing needs the new numbers from finance i'll send those over this afternoon anyway let me know if you want to jump on a call to go through it",
        "right so notes from the call with the supplier they can do the first batch by the twelfth but only five hundred units the full order of two thousand would be end of month pricing is unchanged at four pounds fifty a unit if we pay upfront otherwise four eighty um they also asked about the packaging change we mentioned last time i said we'd come back to them by wednesday oh and one more thing the contact there is now priya not dan dan has moved to the sales team",
    ]

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
