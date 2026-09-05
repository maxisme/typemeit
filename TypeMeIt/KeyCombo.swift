import AppKit
import CoreGraphics
import Foundation
import SwiftUI

/// A key with modifiers, chosen by the user for a global shortcut. The key is
/// held as a virtual keycode so the match does not depend on the keyboard
/// layout, and as the label it had when recorded so it can be shown.
struct KeyCombo: Codable, Equatable, Sendable {
    struct Modifiers: OptionSet, Codable, Sendable {
        let rawValue: UInt8
        static let command = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let control = Modifiers(rawValue: 1 << 2)
        static let shift = Modifiers(rawValue: 1 << 3)

        init(rawValue: UInt8) { self.rawValue = rawValue }

        init(_ flags: CGEventFlags) {
            var m: Modifiers = []
            if flags.contains(.maskCommand) { m.insert(.command) }
            if flags.contains(.maskAlternate) { m.insert(.option) }
            if flags.contains(.maskControl) { m.insert(.control) }
            if flags.contains(.maskShift) { m.insert(.shift) }
            self = m
        }

        init(_ flags: NSEvent.ModifierFlags) {
            var m: Modifiers = []
            if flags.contains(.command) { m.insert(.command) }
            if flags.contains(.option) { m.insert(.option) }
            if flags.contains(.control) { m.insert(.control) }
            if flags.contains(.shift) { m.insert(.shift) }
            self = m
        }

        /// Shift alone would make the shortcut a capital letter, so a combo
        /// needs one of the other three.
        var isEnoughForShortcut: Bool { !intersection([.command, .option, .control]).isEmpty }

        /// In the order the keyboard shows them.
        var symbols: [String] {
            var s: [String] = []
            if contains(.control) { s.append("⌃") }
            if contains(.option) { s.append("⌥") }
            if contains(.shift) { s.append("⇧") }
            if contains(.command) { s.append("⌘") }
            return s
        }
    }

    var keyCode: UInt16
    var modifiers: Modifiers
    var keyLabel: String

    /// Nil when the event is a bare modifier press or lacks a usable modifier.
    init?(event: NSEvent) {
        guard event.type == .keyDown else { return nil }
        let modifiers = Modifiers(event.modifierFlags)
        guard modifiers.isEnoughForShortcut else { return nil }
        guard let label = KeyCombo.label(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers) else { return nil }
        self.keyCode = event.keyCode
        self.modifiers = modifiers
        self.keyLabel = label
    }

    init(keyCode: UInt16, modifiers: Modifiers, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    /// True for the key event of this combo. Flags the user cannot press,
    /// like the numeric-pad or non-coalesced bits, are ignored.
    func matches(keyCode: Int64, flags: CGEventFlags) -> Bool {
        keyCode == Int64(self.keyCode) && Modifiers(flags) == modifiers
    }

    /// For a menu item. Nil for keys SwiftUI menus cannot show, like the F keys.
    var keyboardShortcut: KeyboardShortcut? {
        let key: KeyEquivalent
        switch keyCode {
        case 36: key = .return
        case 48: key = .tab
        case 49: key = .space
        case 51: key = .delete
        case 53: key = .escape
        case 117: key = .deleteForward
        case 115: key = .home
        case 119: key = .end
        case 116: key = .pageUp
        case 121: key = .pageDown
        case 123: key = .leftArrow
        case 124: key = .rightArrow
        case 125: key = .downArrow
        case 126: key = .upArrow
        default:
            guard keyLabel.count == 1, let c = keyLabel.lowercased().first else { return nil }
            key = KeyEquivalent(c)
        }
        var mods: EventModifiers = []
        if modifiers.contains(.command) { mods.insert(.command) }
        if modifiers.contains(.option) { mods.insert(.option) }
        if modifiers.contains(.control) { mods.insert(.control) }
        if modifiers.contains(.shift) { mods.insert(.shift) }
        return KeyboardShortcut(key, modifiers: mods)
    }

    /// The parts as keycaps: modifiers first, then the key.
    var caps: [String] { modifiers.symbols + [keyLabel] }

    private static let specialKeys: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "space", 51: "⌫", 53: "esc", 76: "⌤", 117: "⌦",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟", 123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    static func label(keyCode: UInt16, characters: String?) -> String? {
        if let special = specialKeys[keyCode] { return special }
        guard let characters, let scalar = characters.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar), !CharacterSet.whitespacesAndNewlines.contains(scalar)
        else { return nil }
        return characters.uppercased()
    }
}
