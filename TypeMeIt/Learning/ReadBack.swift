import Foundation

/// Watches the field TypeMeIt pasted into and learns from the user's corrections
/// there. One session at a time; a new recording ends the previous session.
/// Port of the session in learning/readback.rs.
@MainActor
final class ReadBack {
    static let shared = ReadBack()
    private init() {}

    private var current: Task<Void, Never>?

    func start(pasted: String, historyId: UUID?, appId: String?) {
        finishNow()
        guard !SecureInput.isEnabled else { return }
        if let appId, ReadBack.denied(appId) { return }
        current = Task { [weak self] in
            await self?.run(pasted: pasted, historyId: historyId)
        }
    }

    /// Called when a new recording starts: stop watching.
    func finishNow() {
        current?.cancel()
        current = nil
    }

    private static func denied(_ bundle: String) -> Bool {
        Fixed.learningAppDenylist.contains { $0.caseInsensitiveCompare(bundle) == .orderedSame }
    }

    private func run(pasted: String, historyId: UUID?) async {
        try? await Task.sleep(for: ReadBackTiming.settle)
        guard !Task.isCancelled else { return }
        guard let field = FocusedTextField.capture() else {
            Log.learning.debug("readback: no readable text field has focus")
            return
        }
        if let bundle = field.bundleId, ReadBack.denied(bundle) { return }

        var snap: ReadBackText.PasteSnapshot?
        for attempt in 0..<ReadBackTiming.captureAttempts {
            if attempt > 0 { try? await Task.sleep(for: ReadBackTiming.captureRetry) }
            guard !Task.isCancelled else { return }
            guard let value = field.value() else { continue }
            if value.utf8.count > ReadBackText.maxFieldBytes { return }
            let caret = field.selectedRange().map { $0.upperBound }
            if let found = ReadBackText.snapshot(value: value, pasted: pasted, caretUTF16: caret) {
                snap = found
                break
            }
        }
        guard let snap else {
            Log.learning.debug("readback: pasted text not found in the field")
            return
        }

        let placeholder = field.placeholder()
        func cleared(_ value: String) -> Bool {
            let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if v.isEmpty { return true }
            if let p = placeholder, p.trimmingCharacters(in: .whitespacesAndNewlines) == v { return true }
            return false
        }

        let started = ContinuousClock.now
        var lastSpan: String?
        while ContinuousClock.now - started < ReadBackTiming.limit, !Task.isCancelled {
            try? await Task.sleep(for: ReadBackTiming.poll)
            if let value = field.value() {
                if cleared(value) { break }
                if let span = ReadBackText.currentSpan(of: value, snapshot: snap) {
                    if let previous = lastSpan, ReadBackText.replacedWholesale(previous: previous, next: span) { break }
                    lastSpan = span
                } else if lastSpan != nil {
                    break  // text around the paste changed
                }
            }
            if !field.isFocused() { break }
        }

        // One more read: apps that keep the element alive give the text as it
        // was left; apps that drop it fall back to the last intact poll.
        var finalSpan: String?
        if let value = field.value(), !cleared(value), let span = ReadBackText.currentSpan(of: value, snapshot: snap) {
            if let previous = lastSpan, ReadBackText.replacedWholesale(previous: previous, next: span) {
                finalSpan = nil
            } else {
                finalSpan = span
            }
        }
        guard let edited = finalSpan ?? lastSpan else { return }
        guard edited.trimmingCharacters(in: .whitespacesAndNewlines) != snap.pasted.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        LearningCoordinator.shared.learn(original: snap.pasted, edited: edited, source: "readback", historyId: historyId)
    }
}
