import AVFoundation
import ApplicationServices
import CoreGraphics
import Foundation

/// A grant the app cannot dictate without. Each is switched in System
/// Settings, so the app can only notice it has gone and point there.
enum MissingPermission: CaseIterable {
    case microphone, accessibility, inputMonitoring

    var name: String {
        switch self {
        case .microphone: "microphone"
        case .accessibility: "accessibility"
        case .inputMonitoring: "input monitoring"
        }
    }

    /// What stops working without it.
    var consequence: String {
        switch self {
        case .microphone: "nothing can be recorded"
        case .accessibility: "nothing can be typed where your cursor is"
        case .inputMonitoring: "the fn key is not seen"
        }
    }

    var settingsURL: URL {
        switch self {
        case .microphone: SecureInput.microphoneSettingsURL
        case .accessibility: SecureInput.accessibilitySettingsURL
        case .inputMonitoring: SecureInput.inputMonitoringSettingsURL
        }
    }

    var granted: Bool {
        switch self {
        case .microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .accessibility: AXIsProcessTrusted()
        case .inputMonitoring: CGPreflightListenEventAccess()
        }
    }

    /// The first permission that has been taken away, or nil when all hold.
    static var first: MissingPermission? { allCases.first { !$0.granted } }
}
