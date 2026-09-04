// Identifies the application the user is dictating into.
//
// Sampled when a recording stops, which is the last moment before the
// transcription pipeline runs and the user could switch windows. The result
// is stored on the history entry so the insights page can attribute each
// dictation to an app and, through the focused window's title, to what was
// open inside a browser or terminal.

import AppKit
import ApplicationServices
import Foundation

enum Frontmost {
    /// The application that owned keyboard focus when a recording stopped.
    struct Target: Sendable, Equatable {
        /// Stable identifier: the bundle identifier.
        var appId: String?
        /// Human-readable name shown in the insights page.
        var appName: String?
        /// Title of the focused window, when Accessibility exposes it.
        var windowTitle: String?
    }

    /// Frontmost app via `NSWorkspace`; window title via `AXFocusedWindow` ->
    /// `AXTitle` with a 0.5 s messaging timeout, so an unresponsive app never
    /// blocks longer than that. `nil` when there is no frontmost application.
    static func capture() -> Target? {
        guard let running = NSWorkspace.shared.frontmostApplication else { return nil }
        return Target(
            appId: running.bundleIdentifier,
            appName: running.localizedName,
            windowTitle: focusedWindowTitle(pid: running.processIdentifier)
        )
    }

    /// Title of the app's focused window via the accessibility layer. Requires
    /// the Accessibility permission TypeMeIt already needs for pasting; without
    /// it the attribute copy fails with `kAXErrorAPIDisabled` and this
    /// returns `nil`.
    private static func focusedWindowTitle(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        app.applyMessagingTimeout()
        guard case .success(let value) = app.copyAttribute(kAXFocusedWindowAttribute),
              let window = AX.element(value)
        else { return nil }
        window.applyMessagingTimeout()
        guard case .success(let titleValue) = window.copyAttribute(kAXTitleAttribute),
              let title = AX.string(titleValue),
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return title
    }
}
