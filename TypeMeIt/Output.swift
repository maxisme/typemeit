import AppKit
import CoreGraphics
import Foundation

/// Pastes through the clipboard with Cmd+V and restores what was there.
@MainActor
enum Output {
    private static func post(keycode: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keycode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keycode, keyDown: false) else { return false }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    private static func sleep(ms: Int) async {
        try? await Task.sleep(for: .milliseconds(ms))
    }

    /// Returns false when the key events could not be posted (Accessibility missing).
    static func paste(_ text: String, autoSubmit: Bool, autoSubmitKey: AutoSubmitKey) async -> Bool {
        let pb = NSPasteboard.general
        let savedText = pb.string(forType: .string).flatMap { $0.isEmpty ? nil : $0 }
        let savedImage: (Data, NSPasteboard.PasteboardType)? = savedText == nil
            ? ([NSPasteboard.PasteboardType.tiff, .png].lazy.compactMap { t in pb.data(forType: t).map { ($0, t) } }.first)
            : nil

        pb.clearContents()
        pb.setString(text, forType: .string)
        let ourChange = pb.changeCount
        await sleep(ms: Fixed.pasteDelayBeforeMs)

        let posted = post(keycode: 9, flags: .maskCommand)  // V
        if !posted { Log.output.error("Could not post Cmd+V; Accessibility may be missing") }

        await sleep(ms: Fixed.pasteDelayAfterMs)
        // Only restore if the pasteboard still holds the transcript. If the user or
        // another app wrote to it meanwhile, that content wins.
        if pb.changeCount == ourChange {
            pb.clearContents()
            if let savedText {
                pb.setString(savedText, forType: .string)
            } else if let (data, type) = savedImage {
                pb.setData(data, forType: type)
            }
        }

        if posted, autoSubmit {
            await sleep(ms: Fixed.autoSubmitDelayMs)
            let flags: CGEventFlags = switch autoSubmitKey {
            case .enter: []
            case .ctrlEnter: .maskControl
            case .cmdEnter: .maskCommand
            }
            _ = post(keycode: 36, flags: flags)  // Return
        }
        return posted
    }

    static func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}
