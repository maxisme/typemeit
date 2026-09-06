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
        Case(input: "so i've been thinking about the onboarding flow and i want to write down where i've got to before i forget the main problem is that people drop off at the permissions step we ask for microphone accessibility and input monitoring all in one go and it's too much at once what i'd like to try is asking for the microphone first because that's the one people understand and then only asking for the other two the first time they actually try to dictate into another app that way the ask comes with a reason attached the second thing is the welcome screen it's got too much text nobody reads it i think we cut it down to one line and a single button and move everything else into the settings window where people can find it later on a completely different note i talked to james about the pricing and he thinks we should drop the monthly plan and just do a one off purchase with a year of updates his argument is that a dictation app isn't a subscription kind of product and i think he's probably right we'd need to change the website and the licence server so that's not a small job but worth doing before the launch and finally can someone check the crash reports from last week there were three from the same machine and i want to know if it's the audio device switching bug again",
             expected: [
                """
                So I've been thinking about the onboarding flow and I want to write down where I've got to before I forget. The main problem is that people drop off at the permissions step. We ask for microphone, accessibility and input monitoring all in one go and it's too much at once. What I'd like to try is asking for the microphone first, because that's the one people understand, and then only asking for the other two the first time they actually try to dictate into another app. That way the ask comes with a reason attached.

                The second thing is the welcome screen. It's got too much text, nobody reads it. I think we cut it down to one line and a single button and move everything else into the settings window where people can find it later.

                On a completely different note, I talked to James about the pricing and he thinks we should drop the monthly plan and just do a one-off purchase with a year of updates. His argument is that a dictation app isn't a subscription kind of product and I think he's probably right. We'd need to change the website and the licence server so that's not a small job, but worth doing before the launch.

                And finally, can someone check the crash reports from last week? There were three from the same machine and I want to know if it's the audio device switching bug again.
                """,
             ]),
        Case(input: "hi everyone quick update from the week so on the transcription side we swapped the speech model over to the new version on tuesday and the word error rate on our test set went from about eight percent down to just under six which is a nice jump the main gain is on names and technical words the old model was terrible at anything it hadn't seen before latency is about the same maybe slightly worse on the older machines so we should keep an eye on that on the clean up side we've been going back and forth on the apple intelligence prompt it now fixes obvious mishearings which was the big complaint but it still drops words sometimes in short sentences and we haven't found a way to make it format longer dictations into paragraphs we tried four different approaches and none of them worked so we're now benchmarking a couple of open models that could run alongside it more on that next week the design side has been quiet the new settings window is in review and the cloud icon is done i think we're about a week away from being able to show it to people outside the team on the business side we had two calls with potential partners neither of them are a fit right now but both said to come back after the launch and lastly a reminder that i'm off thursday and friday so if you need anything from me get it in by wednesday afternoon thanks all",
             expected: [
                """
                Hi everyone, quick update from the week.

                So on the transcription side, we swapped the speech model over to the new version on Tuesday and the word error rate on our test set went from about 8% down to just under 6%, which is a nice jump. The main gain is on names and technical words. The old model was terrible at anything it hadn't seen before. Latency is about the same, maybe slightly worse on the older machines, so we should keep an eye on that.

                On the clean up side, we've been going back and forth on the Apple Intelligence prompt. It now fixes obvious mishearings, which was the big complaint, but it still drops words sometimes in short sentences and we haven't found a way to make it format longer dictations into paragraphs. We tried four different approaches and none of them worked, so we're now benchmarking a couple of open models that could run alongside it. More on that next week.

                The design side has been quiet. The new settings window is in review and the cloud icon is done. I think we're about a week away from being able to show it to people outside the team.

                On the business side, we had two calls with potential partners. Neither of them are a fit right now but both said to come back after the launch.

                And lastly, a reminder that I'm off Thursday and Friday, so if you need anything from me get it in by Wednesday afternoon. Thanks all.
                """,
                """
                Hi everyone, quick update from the week. So on the transcription side, we swapped the speech model over to the new version on Tuesday and the word error rate on our test set went from about 8% down to just under 6%, which is a nice jump. The main gain is on names and technical words. The old model was terrible at anything it hadn't seen before. Latency is about the same, maybe slightly worse on the older machines, so we should keep an eye on that.

                On the clean up side, we've been going back and forth on the Apple Intelligence prompt. It now fixes obvious mishearings, which was the big complaint, but it still drops words sometimes in short sentences and we haven't found a way to make it format longer dictations into paragraphs. We tried four different approaches and none of them worked, so we're now benchmarking a couple of open models that could run alongside it. More on that next week.

                The design side has been quiet. The new settings window is in review and the cloud icon is done. I think we're about a week away from being able to show it to people outside the team.

                On the business side, we had two calls with potential partners. Neither of them are a fit right now but both said to come back after the launch.

                And lastly, a reminder that I'm off Thursday and Friday, so if you need anything from me get it in by Wednesday afternoon. Thanks all.
                """,
             ]),
    ]

    /// The shape of a layout: how many paragraphs, the first two words of each,
    /// and how many numbered lines. Wording is free to drift; where the breaks
    /// fall is not. A blank line before a numbered list does not count as a break.
    struct Layout: Equatable { var paragraphStarts: [String]; var numberedLines: Int }

    static func layout(_ s: String) -> Layout {
        var starts: [String] = []
        var numbered = 0
        var atParagraphStart = true
        for raw in s.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { atParagraphStart = true; continue }
            let isNumbered = line.first?.isNumber == true && (line.contains(". ") || line.hasSuffix("."))
            if isNumbered { numbered += 1 }
            if atParagraphStart, !isNumbered { starts.append(normalise(line).split(separator: " ").prefix(2).joined(separator: " ")) }
            atParagraphStart = false
        }
        return Layout(paragraphStarts: starts, numberedLines: numbered)
    }

    /// Share of the expected words present in the output, to catch dropped content behind a good-looking layout.
    static func wordRecall(expected: String, got: String) -> Double {
        let e = Set(normalise(expected).split(separator: " ")), g = Set(normalise(got).split(separator: " "))
        return e.isEmpty ? 0 : Double(e.intersection(g).count) / Double(e.count)
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
