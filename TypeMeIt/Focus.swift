// Asks the Accessibility layer whether the element that currently has keyboard
// focus accepts typed text, and captures that element for later read-back.
//
// Used right before a transcript is pasted: when nothing editable is focused
// the paste chord lands nowhere, so the coordinator offers the transcript on
// the overlay instead (copy prompt).
//
// The answer is tri-state. `nil` means the system gave no usable answer
// (Accessibility not granted, the API refused, no frontmost app) and callers
// must not draw conclusions from it.

import AppKit
import ApplicationServices
import Foundation

enum Focus {
    /// Accessibility roles that always take typed text.
    static let textRoles: [String] = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    /// The role (and, in web content, subrole) of a password field.
    static let secureTextRole = "AXSecureTextField"

    /// Pure classification: a known text role, or any element whose `AXValue`
    /// the accessibility layer lets us set (editable web content, code editors
    /// and terminals that report a generic role but writable text).
    static func classifyRole(_ role: String, valueSettable: Bool) -> Bool {
        textRoles.contains(role) || valueSettable
    }

    /// Pure check: a field whose contents must never be read back. Native
    /// password fields report the role; WebKit reports a generic text role
    /// with the secure subrole.
    static func roleIsSecure(_ role: String, subrole: String?) -> Bool {
        role == secureTextRole || subrole == secureTextRole
    }

    /// Converts a `CFRange` (signed, `kCFNotFound` = -1 for "no range") into
    /// a half-open range of UTF-16 offsets. Either bound negative means no
    /// selection.
    static func utf16Range(location: CFIndex, length: CFIndex) -> Range<Int>? {
        guard location >= 0, length >= 0 else { return nil }
        return location..<(location + length)
    }

    /// `true` when the focused element takes text input, `false` when it
    /// definitely does not (including "nothing is focused"), `nil` when
    /// Accessibility is not granted or the focused element cannot be read.
    static func focusedElementIsTextInput() -> Bool? {
        let systemWide = AXUIElementCreateSystemWide()
        systemWide.applyMessagingTimeout()

        let focused: AXUIElement
        switch systemWide.copyAttribute(kAXFocusedUIElementAttribute) {
        case .success(let value):
            guard let element = AX.element(value) else { return nil }
            focused = element
        case .failure(let error) where error.code == .noValue:
            return false
        case .failure:
            return nil
        }
        focused.applyMessagingTimeout()

        guard case .success(let role) = focused.copyStringAttribute(kAXRoleAttribute) else {
            return nil
        }
        let valueSettable = focused.isAttributeSettable(kAXValueAttribute)
        return classifyRole(role, valueSettable: valueSettable)
    }
}

/// A text field that had keyboard focus when captured. Holds a retained
/// `AXUIElement`; AXUIElement messaging is thread-safe, so the handle may be
/// read from any thread. Every method only issues read-only requests.
final class FocusedTextField: @unchecked Sendable {
    private let element: AXUIElement
    /// Process id of the owning application, read once at capture.
    let pid: pid_t?

    private init(element: AXUIElement, pid: pid_t?) {
        self.element = element
        self.pid = pid
    }

    /// The system-wide focused element, if it is an editable text field that
    /// may be read back. `nil` when nothing is focused, when the element is
    /// not a text input, or when it is a secure (password) field.
    static func capture() -> FocusedTextField? {
        let systemWide = AXUIElementCreateSystemWide()
        systemWide.applyMessagingTimeout()
        return fromFocusedElement(of: systemWide)
    }

    /// The focused element of one application, resolved through that
    /// application's own accessibility element instead of the system-wide
    /// one. The system-wide lookup fails with `kAXErrorCannotComplete` from a
    /// plain shell process, so tools that read a known application use this.
    static func capture(inApplication pid: pid_t) -> FocusedTextField? {
        let app = AXUIElementCreateApplication(pid)
        app.applyMessagingTimeout()
        return fromFocusedElement(of: app)
    }

    /// Reads `AXFocusedUIElement` of `parent` and wraps it if it is a
    /// readable text field.
    private static func fromFocusedElement(of parent: AXUIElement) -> FocusedTextField? {
        guard case .success(let value) = parent.copyAttribute(kAXFocusedUIElementAttribute),
              let element = AX.element(value)
        else { return nil }
        // The handle outlives `parent` and is messaged again later, so it
        // carries its own timeout.
        element.applyMessagingTimeout()

        guard case .success(let role) = element.copyStringAttribute(kAXRoleAttribute) else {
            return nil
        }
        let subrole: String?
        if case .success(let value) = element.copyStringAttribute(kAXSubroleAttribute) {
            subrole = value
        } else {
            subrole = nil
        }
        if Focus.roleIsSecure(role, subrole: subrole) {
            return nil
        }
        let valueSettable = element.isAttributeSettable(kAXValueAttribute)
        guard Focus.classifyRole(role, valueSettable: valueSettable) else {
            return nil
        }

        var pid: pid_t = 0
        let err = AXUIElementGetPid(element, &pid)
        let owner: pid_t? = (err == .success && pid > 0) ? pid : nil
        return FocusedTextField(element: element, pid: owner)
    }

    /// Bundle identifier of the owning application. `nil` if the process is
    /// unknown, has exited, or is not an application bundle.
    var bundleId: String? {
        guard let pid else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    /// The field's current text (`AXValue` as a string). `nil` if the element
    /// is gone, the attribute cannot be read, or the value is not a string;
    /// never a truncated string.
    func value() -> String? {
        guard case .success(let value) = element.copyAttribute(kAXValueAttribute) else {
            return nil
        }
        return AX.string(value)
    }

    /// The field's placeholder (`AXPlaceholderValue`), shown when it is
    /// empty. Some toolkits report it as the value once the text is gone.
    func placeholder() -> String? {
        guard case .success(let text) = element.copyStringAttribute(kAXPlaceholderValueAttribute),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return text
    }

    /// The selection as UTF-16 offsets from `AXSelectedTextRange`. `nil` if
    /// unavailable.
    func selectedRange() -> Range<Int>? {
        guard case .success(let value) = element.copyAttribute(kAXSelectedTextRangeAttribute),
              CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return Focus.utf16Range(location: range.location, length: range.length)
    }

    /// True while this element is still the system-wide focused element.
    func isFocused() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        systemWide.applyMessagingTimeout()
        guard case .success(let focused) = systemWide.copyAttribute(kAXFocusedUIElementAttribute) else {
            return false
        }
        return CFEqual(focused, element)
    }
}

/// A failed accessibility request, carrying the `AXError` the API reported.
struct AXRequestError: Error, Equatable {
    let code: AXError
}

/// Helpers shared by the focus and frontmost queries.
enum AX {
    /// Upper bound on how long a single accessibility request may block. The
    /// focus query runs right before the paste and the frontmost probe on the
    /// shortcut thread, so an unresponsive app must not stall either for the
    /// default six seconds.
    static let messagingTimeoutSeconds: Float = 0.5

    /// `value` as an `AXUIElement`, or `nil` when it is some other CF type.
    static func element(_ value: CFTypeRef) -> AXUIElement? {
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// `value` as a Swift string, or `nil` when it is not a `CFString`.
    static func string(_ value: CFTypeRef) -> String? {
        guard CFGetTypeID(value) == CFStringGetTypeID() else { return nil }
        return (value as! CFString) as String
    }
}

extension AXUIElement {
    func applyMessagingTimeout() {
        AXUIElementSetMessagingTimeout(self, AX.messagingTimeoutSeconds)
    }

    /// Copies an attribute value (Copy rule: the caller owns the result). A
    /// successful request that yields no object reads as `.noValue`.
    func copyAttribute(_ name: String) -> Result<CFTypeRef, AXRequestError> {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(self, name as CFString, &value)
        guard err == .success else { return .failure(AXRequestError(code: err)) }
        guard let value else { return .failure(AXRequestError(code: .noValue)) }
        return .success(value)
    }

    /// Copies a string attribute. A value that is not a `CFString` reads as
    /// the empty string; a failed request is the error.
    func copyStringAttribute(_ name: String) -> Result<String, AXRequestError> {
        copyAttribute(name).map { AX.string($0) ?? "" }
    }

    func isAttributeSettable(_ name: String) -> Bool {
        var settable: DarwinBoolean = false
        let err = AXUIElementIsAttributeSettable(self, name as CFString, &settable)
        return err == .success && settable.boolValue
    }
}
