import AppKit
import Carbon.HIToolbox
import Foundation
import IOKit

enum SecureInput {
    /// True while another app (a password field) has Secure Input on. Event
    /// taps still receive modifier changes, so Fn works, but no key presses:
    /// esc, space and the copy shortcut do not reach the app.
    static var isEnabled: Bool { IsSecureEventInputEnabled() }

    /// The process holding Secure Input, or nil when it is off.
    struct Owner: Equatable {
        var name: String
        /// loginwindow keeps Secure Input after the screen is unlocked and
        /// does not release it until the Mac is locked and unlocked again.
        var isLoginWindow: Bool { name == "loginwindow" }
    }

    static var owner: Owner? {
        guard isEnabled, let pid = ownerPID else { return nil }
        if let app = NSRunningApplication(processIdentifier: pid), let name = app.localizedName {
            return Owner(name: name)
        }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return Owner(name: String(cString: buffer))
    }

    /// The window server records the holder's pid on the console session in
    /// the IORegistry root; there is no public API for it.
    private static var ownerPID: pid_t? {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        let property = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        guard let sessions = property as? [[String: Any]] else { return nil }
        return sessions.lazy.compactMap { $0["kCGSSessionSecureInputPID"] as? pid_t }.first
    }

    /// "Press 🌐 key to" in System Settings > Keyboard. 0 means Do Nothing,
    /// which TypeMeIt needs so the release of Fn does not open the emoji picker.
    static var fnKeyDoesNothing: Bool {
        let value = CFPreferencesCopyAppValue("AppleFnUsageType" as CFString, "com.apple.HIToolbox" as CFString)
        guard let value else { return false }
        return (value as? NSNumber)?.intValue == 0
    }

    static let keyboardSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
    static let appleIntelligenceSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!
    static let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    static let inputMonitoringSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
    static let microphoneSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
    static let screenRecordingSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
}
