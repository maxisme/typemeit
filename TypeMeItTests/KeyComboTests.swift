import CoreGraphics
import Foundation
import Testing
@testable import TypeMeIt

struct KeyComboTests {
    let combo = KeyCombo(keyCode: 8, modifiers: [.command, .shift], keyLabel: "C")

    @Test func matchesTheSameKeyAndModifiers() {
        #expect(combo.matches(keyCode: 8, flags: [.maskCommand, .maskShift]))
    }

    @Test func ignoresFlagsTheUserCannotPress() {
        #expect(combo.matches(keyCode: 8, flags: [.maskCommand, .maskShift, .maskNonCoalesced, .maskNumericPad]))
    }

    @Test func rejectsAnotherKeyOrModifierSet() {
        #expect(!combo.matches(keyCode: 9, flags: [.maskCommand, .maskShift]))
        #expect(!combo.matches(keyCode: 8, flags: [.maskCommand]))
        #expect(!combo.matches(keyCode: 8, flags: [.maskCommand, .maskShift, .maskAlternate]))
    }

    @Test func shiftAloneIsNotEnough() {
        #expect(!KeyCombo.Modifiers.shift.isEnoughForShortcut)
        #expect(KeyCombo.Modifiers.option.isEnoughForShortcut)
    }

    @Test func capsListModifiersThenKey() {
        #expect(combo.caps == ["⇧", "⌘", "C"])
    }

    @Test func labelsSpecialKeysAndUppercasesCharacters() {
        #expect(KeyCombo.label(keyCode: 49, characters: " ") == "space")
        #expect(KeyCombo.label(keyCode: 122, characters: "\u{F704}") == "F1")
        #expect(KeyCombo.label(keyCode: 0, characters: "a") == "A")
        #expect(KeyCombo.label(keyCode: 55, characters: nil) == nil)
    }

    @Test func roundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(combo)
        #expect(try JSONDecoder().decode(KeyCombo.self, from: data) == combo)
    }
}
