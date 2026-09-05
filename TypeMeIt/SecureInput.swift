import Carbon.HIToolbox
import Foundation

enum SecureInput {
    /// True while another app (a password field) has Secure Input on. Event
    /// taps receive no keyboard events in that state.
    static var isEnabled: Bool { IsSecureEventInputEnabled() }

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
