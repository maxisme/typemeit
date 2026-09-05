import Foundation
import Observation

enum AutoSubmitKey: String, Codable, CaseIterable, Sendable {
    case enter, ctrlEnter, cmdEnter

    var label: String {
        switch self {
        case .enter: "Return"
        case .ctrlEnter: "Control-Return"
        case .cmdEnter: "Command-Return"
        }
    }
}

/// Every user-changeable value, backed by UserDefaults. Fixed values that are
/// not settings live in `Fixed`.
@MainActor
@Observable
final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    var microphoneUID: String? { didSet { defaults.set(microphoneUID, forKey: "microphoneUID") } }
    var alwaysOnMicrophone: Bool { didSet { defaults.set(alwaysOnMicrophone, forKey: "alwaysOnMicrophone") } }
    var muteWhileRecording: Bool { didSet { defaults.set(muteWhileRecording, forKey: "muteWhileRecording") } }
    var audioFeedback: Bool { didSet { defaults.set(audioFeedback, forKey: "audioFeedback") } }
    var overlayEnabled: Bool { didSet { defaults.set(overlayEnabled, forKey: "overlayEnabled") } }
    var copyPromptEnabled: Bool { didSet { defaults.set(copyPromptEnabled, forKey: "copyPromptEnabled") } }
    var postProcessingEnabled: Bool { didSet { defaults.set(postProcessingEnabled, forKey: "postProcessingEnabled") } }
    var customWords: [String] { didSet { defaults.set(customWords, forKey: "customWords") } }
    var learnFromCorrections: Bool { didSet { defaults.set(learnFromCorrections, forKey: "learnFromCorrections") } }
    var appendTrailingSpace: Bool { didSet { defaults.set(appendTrailingSpace, forKey: "appendTrailingSpace") } }
    var autoSubmit: Bool { didSet { defaults.set(autoSubmit, forKey: "autoSubmit") } }
    var autoSubmitKey: AutoSubmitKey { didSet { defaults.set(autoSubmitKey.rawValue, forKey: "autoSubmitKey") } }
    var historyLimit: Int { didSet { defaults.set(historyLimit, forKey: "historyLimit") } }
    var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: "launchAtLogin") } }
    var showDockIcon: Bool { didSet { defaults.set(showDockIcon, forKey: "showDockIcon") } }
    var onboardingComplete: Bool { didSet { defaults.set(onboardingComplete, forKey: "onboardingComplete") } }
    /// Words removed by the learned-words toast's Undo. Never learned again.
    var undoneWords: [String] { didSet { defaults.set(undoneWords, forKey: "undoneWords") } }

    private init() {
        let d = UserDefaults.standard
        func bool(_ key: String, _ fallback: Bool) -> Bool { d.object(forKey: key) == nil ? fallback : d.bool(forKey: key) }
        microphoneUID = d.string(forKey: "microphoneUID")
        alwaysOnMicrophone = bool("alwaysOnMicrophone", false)
        muteWhileRecording = bool("muteWhileRecording", true)
        audioFeedback = bool("audioFeedback", true)
        overlayEnabled = bool("overlayEnabled", true)
        copyPromptEnabled = bool("copyPromptEnabled", true)
        postProcessingEnabled = bool("postProcessingEnabled", true)
        customWords = d.stringArray(forKey: "customWords") ?? []
        learnFromCorrections = bool("learnFromCorrections", true)
        appendTrailingSpace = bool("appendTrailingSpace", true)
        autoSubmit = bool("autoSubmit", false)
        autoSubmitKey = AutoSubmitKey(rawValue: d.string(forKey: "autoSubmitKey") ?? "") ?? .enter
        historyLimit = d.object(forKey: "historyLimit") == nil ? 500 : d.integer(forKey: "historyLimit")
        launchAtLogin = bool("launchAtLogin", false)
        showDockIcon = bool("showDockIcon", true)
        onboardingComplete = bool("onboardingComplete", false)
        undoneWords = d.stringArray(forKey: "undoneWords") ?? []
    }

    func addCustomWord(_ word: String) {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty, !customWords.contains(where: { $0.caseInsensitiveCompare(w) == .orderedSame }) else { return }
        customWords.append(w)
    }

    func removeCustomWord(_ word: String) {
        customWords.removeAll { $0.caseInsensitiveCompare(word) == .orderedSame }
    }
}

/// Values that are built in and have no UI.
enum AppVersion {
    static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
}

enum Fixed {
    static let websiteURL = URL(string: "https://typeme.it")!
    static let holdThresholdMs = 300
    static let wordCorrectionThreshold = 0.18
    static let pasteDelayBeforeMs = 60
    static let pasteDelayAfterMs = 60
    static let autoSubmitDelayMs = 50
    static let modelUnloadIdle: Duration = .seconds(5 * 60)
    static let copyPromptTimeout: Duration = .seconds(8)
    static let minimumRecordingSeconds = 0.3
    static let silencePeak: Float = 0.01
    static let learningAppDenylist: Set<String> = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
        "com.lastpass.LastPass", "com.apple.keychainaccess", "com.apple.Terminal",
        "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
    ]
}
