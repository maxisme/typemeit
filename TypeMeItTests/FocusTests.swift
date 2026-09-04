import Testing
@testable import TypeMeIt

struct FocusTests {
    @Test func textRolesAreTextInputs() {
        for role in Focus.textRoles {
            #expect(Focus.classifyRole(role, valueSettable: false), "\(role)")
        }
    }

    @Test func genericRoleWithSettableValueIsTextInput() {
        #expect(Focus.classifyRole("AXWebArea", valueSettable: true))
    }

    @Test func staticContentIsNotTextInput() {
        #expect(!Focus.classifyRole("AXStaticText", valueSettable: false))
        #expect(!Focus.classifyRole("AXButton", valueSettable: false))
        #expect(!Focus.classifyRole("", valueSettable: false))
    }

    @Test func secureRoleOrSubroleIsSecure() {
        #expect(Focus.roleIsSecure("AXSecureTextField", subrole: nil))
        #expect(Focus.roleIsSecure("AXTextField", subrole: "AXSecureTextField"))
        #expect(Focus.roleIsSecure("AXSecureTextField", subrole: "AXSecureTextField"))
    }

    @Test func plainTextFieldIsNotSecure() {
        #expect(!Focus.roleIsSecure("AXTextField", subrole: nil))
        #expect(!Focus.roleIsSecure("AXTextField", subrole: "AXSearchField"))
        #expect(!Focus.roleIsSecure("AXTextArea", subrole: ""))
        #expect(!Focus.roleIsSecure("", subrole: nil))
    }

    @Test func utf16RangeAcceptsNonNegativeBounds() {
        #expect(Focus.utf16Range(location: 0, length: 0) == 0..<0)
        #expect(Focus.utf16Range(location: 7, length: 3) == 7..<10)
    }

    @Test func utf16RangeRejectsNegativeBounds() {
        #expect(Focus.utf16Range(location: -1, length: 0) == nil)
        #expect(Focus.utf16Range(location: 0, length: -1) == nil)
        #expect(Focus.utf16Range(location: -1, length: -1) == nil)
    }
}
