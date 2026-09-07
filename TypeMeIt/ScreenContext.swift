// Spike: reads the text on the user's screen while they dictate, so the
// clean-up model knows the names and terms the speaker is probably looking
// at. A grabbed frame of the frontmost window goes through Vision's text
// recogniser; the lines it returns are boiled down to the words worth
// telling the model about (names, jargon, identifiers) and the frame is
// discarded. Needs Screen Recording, like `ScreenSampler`.

import AppKit
import ScreenCaptureKit
import Vision

enum ScreenContext {
    /// How many terms the prompt is allowed to carry. The on-device model's
    /// window is small and long lists dilute the transcript.
    static let maxTerms = 40

    /// Recognised text lines from the frontmost on-screen window of `pid`.
    /// Empty when the grant is missing, the app has no window, or nothing
    /// was read. Never throws: screen context is best effort.
    static func captureLines(pid: pid_t) async -> [String] {
        guard CGPreflightScreenCaptureAccess() else { return [] }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return [] }
        // Windows come front to back; the first sizeable one owned by the app
        // is the one the user is looking at. Tiny ones are tooltips and panels.
        guard let window = content.windows.first(where: {
            $0.owningApplication?.processID == pid && $0.frame.width > 200 && $0.frame.height > 100
        }) else { return [] }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.showsCursor = false
        config.captureResolution = .best
        config.width = Int(window.frame.width * 2)
        config.height = Int(window.frame.height * 2)
        let start = ContinuousClock.now
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { return [] }
        let lines = await recognise(image)
        let elapsed = ContinuousClock.now - start
        let ms = Int(elapsed.components.seconds * 1000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
        Log.screenContext.info("Read \(lines.count) lines from \(window.owningApplication?.applicationName ?? "?", privacy: .public) in \(ms) ms")
        return lines
    }

    /// Vision's accurate recogniser without language correction: correction
    /// "fixes" exactly the unusual spellings this is trying to keep.
    static func recognise(_ image: CGImage) async -> [String] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = true
        guard let observations = try? await request.perform(on: image) else { return [] }
        return observations.compactMap { $0.topCandidates(1).first?.string }
    }

    /// The words in `lines` worth telling the model about: anything that is
    /// not an ordinary dictionary word (a name, a product, an identifier), or
    /// that is capitalised where it would otherwise not be. `isKnownWord`
    /// says whether a lowercase word is in the dictionary; it is injected so
    /// the rule can be tested without a spell checker. Words already in
    /// `excluding` (the custom words list) are left out, since the prompt
    /// already carries them. Ordered by how often each appeared.
    static func terms(from lines: [String], excluding: [String] = [], isKnownWord: (String) -> Bool) -> [String] {
        var counts: [String: (spelling: String, count: Int)] = [:]
        let excluded = Set(excluding.map { $0.lowercased() })
        for line in lines {
            for raw in line.split(whereSeparator: { $0.isWhitespace }) {
                guard let token = clean(String(raw)) else { continue }
                let key = token.lowercased()
                if excluded.contains(key) { continue }
                guard isCandidate(token, isKnownWord: isKnownWord) else { continue }
                if var existing = counts[key] {
                    existing.count += 1
                    counts[key] = existing
                } else {
                    counts[key] = (token, 1)
                }
            }
        }
        return counts.values
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.spelling < $1.spelling }
            .prefix(maxTerms)
            .map(\.spelling)
    }

    /// Strips surrounding punctuation and rejects tokens that are not words:
    /// numbers, URLs, paths, single characters, long runs.
    static func clean(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols).subtracting(CharacterSet(charactersIn: "@#")))
        guard trimmed.count >= 2, trimmed.count <= 30 else { return nil }
        guard trimmed.contains(where: \.isLetter) else { return nil }
        if trimmed.contains("/") || trimmed.contains("://") || trimmed.contains("\\") { return nil }
        // "example.com" is a domain, not a term; "Node.js" is fine either way.
        if trimmed.filter({ $0 == "." }).count > 1 { return nil }
        return trimmed
    }

    /// A word earns a place when a speech model would plausibly misspell it:
    /// it is not in the dictionary, or it is written in a shape (ALLCAPS,
    /// camelCase, letters with digits, @handle) that spelling alone would not
    /// produce. Ordinary capitalised words ("The", "Monday") are dictionary
    /// words and are dropped.
    static func isCandidate(_ token: String, isKnownWord: (String) -> Bool) -> Bool {
        if token.hasPrefix("@") || token.hasPrefix("#") { return token.count >= 3 }
        let letters = token.filter(\.isLetter)
        let hasDigit = token.contains(where: \.isNumber)
        if hasDigit { return letters.count >= 2 }
        let upper = letters.filter(\.isUppercase).count
        if upper >= 2, upper == letters.count, letters.count >= 2, letters.count <= 6 { return true } // acronym
        if upper >= 1, !token.first!.isUppercase { return true } // camelCase, iPhone
        if upper >= 2 { return true } // McDonald, GitHub
        // Everything else stands or falls on the dictionary. Case-folded so
        // that "Zentryx" and "zentryx" both count as unknown.
        return !isKnownWord(token.lowercased())
    }

    /// `terms(from:)` with the system spell checker for the user's language.
    @MainActor
    static func terms(from lines: [String], excluding: [String]) -> [String] {
        let checker = NSSpellChecker.shared
        return terms(from: lines, excluding: excluding) { word in
            let range = checker.checkSpelling(of: word, startingAt: 0)
            return range.location == NSNotFound
        }
    }
}
