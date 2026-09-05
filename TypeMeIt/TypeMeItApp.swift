import AppKit
import FoundationModels
import ServiceManagement
import SwiftUI

@main
struct TypeMeItApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.menu)

        Window("settings", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 640, height: 520)
    }
}

/// State the menu bar item and windows observe.
@MainActor
@Observable
final class AppState {
    static let shared = AppState()
    var secureInputOn = false
    var recording = false
    var transcribing = false
    var ready = false
    /// The tab the settings window should show when next opened from the
    /// menu, if any. Cleared once the window has moved there.
    var settingsTab: SettingsTab?

    var menuBarImage: NSImage {
        MenuBarIconRenderer.puff(recording: recording, transcribing: transcribing, secureInput: secureInputOn)
    }
}

/// The menu bar image. It is always on screen, so it also holds the window
/// opener for callers outside SwiftUI: the app delegate asks for the settings
/// window through it when the app is reopened from the Dock or Finder.
struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow
    @State private var appState = AppState.shared

    static let openSettings = Notification.Name("it.typeme.openSettings")

    var body: some View {
        Image(nsImage: appState.menuBarImage)
            .onReceive(NotificationCenter.default.publisher(for: MenuBarLabel.openSettings)) { _ in
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}

struct MenuContent: View {
    @Environment(\.openWindow) private var openWindow
    @State private var appState = AppState.shared
    @State private var store = Store.shared

    /// The newest five with any text; a dictation that came out empty has
    /// nothing to copy.
    private var recentTranscripts: [HistoryEntry] {
        Array(store.history.filter { !$0.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.suffix(5).reversed())
    }

    var body: some View {
        if appState.secureInputOn {
            Text("Secure Input is on in another app. Fn is unavailable.")
            Divider()
        }
        Button("Type Me It") { openWindow(id: "settings"); NSApp.activate(ignoringOtherApps: true) }.keyboardShortcut(",", modifiers: .command)
        Divider()
        if Pipeline.shared.phase == .recording {
            Button("Stop Recording") { Pipeline.shared.shortcuts.stopFromMenu() }
        } else {
            Button("Start Recording") { Pipeline.shared.shortcuts.startFromMenu() }
                .disabled(Pipeline.shared.isBusy || !appState.ready)
        }
        if Pipeline.shared.isBusy {
            Button("Cancel Recording") { Pipeline.shared.shortcuts.cancelFromOverlay() }
        }
        Divider()
        Text("Last five transcripts")
        if recentTranscripts.isEmpty {
            Text("No transcripts yet").disabled(true)
        }
        ForEach(Array(recentTranscripts.enumerated()), id: \.element.id) { i, entry in
            let button = Button(MenuContent.title(for: entry.displayText)) { Output.copyToClipboard(entry.displayText) }
            if i == 0 {
                button.keyboardShortcut("c", modifiers: .command)
            } else {
                button
            }
        }
        if !recentTranscripts.isEmpty {
            Button {
                appState.settingsTab = .history
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            } label: { Label { Text("**View All…**") } icon: { Image("akar-history") } }
        }
        Divider()
        Button("Quit Type Me It") { NSApp.terminate(nil) }.keyboardShortcut("q", modifiers: .command)
    }

    /// One line of the transcript, cut so the menu stays narrow.
    static func title(for text: String, limit: Int = 48) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// SwiftUI installs its own object as `NSApp.delegate` and forwards to
    /// this one, so `NSApp.delegate as? AppDelegate` is always nil. Views
    /// reach the delegate through here instead.
    private(set) static var shared: AppDelegate?

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    private var gateWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var secureInputTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = Settings.shared
        _ = Store.shared
        applyDockIcon()
        applyAppearance()
        switch PostProcessor.availability {
        case .available:
            break
        case .unavailable(let reason):
            showGate(reason)
            return
        }
        if Settings.shared.onboardingComplete, ModelStore.isInstalled, OnboardingView.permissionsGranted {
            startRunning()
        } else {
            showOnboarding()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if onboardingWindow?.isVisible == true {
            onboardingWindow?.makeKeyAndOrderFront(nil)
        } else if gateWindow?.isVisible != true {
            NotificationCenter.default.post(name: MenuBarLabel.openSettings, object: nil)
        }
        return false
    }

    /// Launch sequence step 4 onwards.
    func startRunning() {
        Pipeline.shared.start()
        AppState.shared.ready = true
        observePipeline()
        previewToastIfAsked()
        secureInputTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in AppState.shared.secureInputOn = SecureInput.isEnabled }
        }
        // Touch the updater so Sparkle's scheduled check starts even if the menu
        // has never been opened.
        _ = Updates.shared
        reconcileLaunchAtLogin()
    }

    private func observePipeline() {
        // Mirror the pipeline phase into the menu bar icon.
        withObservationTracking {
            let phase = Pipeline.shared.phase
            AppState.shared.recording = phase == .recording
            AppState.shared.transcribing = phase == .transcribing || phase == .cleaningUp
        } onChange: {
            Task { @MainActor in self.observePipeline() }
        }
    }

    func reconcileLaunchAtLogin() {
        let want = Settings.shared.launchAtLogin
        let service = SMAppService.mainApp
        let enabled = service.status == .enabled
        guard want != enabled else { return }
        do {
            if want { try service.register() } else { try service.unregister() }
        } catch {
            Log.app.error("Launch at login could not be changed: \(error.localizedDescription)")
        }
    }

    /// Info.plist launches the app as an agent; the Dock icon is opted into
    /// here so the setting can flip it without a relaunch.
    func applyDockIcon() {
        NSApp.setActivationPolicy(Settings.shared.showDockIcon ? .regular : .accessory)
        // The Dock caches an icon per bundle path, so a rebuilt dev app can
        // keep showing the release icon it had before; setting the running
        // app's own icon sidesteps the cache.
        if Updates.isDevBuild, let url = Bundle.main.url(forResource: "AppIcon-Dev", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
    }

    /// Every window, the overlay panel included, takes the app's appearance,
    /// so this is the one place the setting is applied.
    func applyAppearance() {
        NSApp.appearance = Settings.shared.appearance.nsAppearance
    }

    /// `-previewToast "word,word"` shows the learned-words toast a moment
    /// after launch, for looking at it without dictating.
    private func previewToastIfAsked() {
        guard let words = UserDefaults.standard.string(forKey: "previewToast"), !words.isEmpty else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            Pipeline.shared.showLearnedToast(batchId: UUID(), words: words.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) })
        }
    }

    // MARK: Windows

    private func showGate(_ reason: SystemLanguageModel.Availability.UnavailableReason) {
        let view = GateView(reason: reason)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Type Me It needs Apple Intelligence"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        gateWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func showOnboarding() {
        if let w = onboardingWindow { NSApp.activate(ignoringOtherApps: true); w.makeKeyAndOrderFront(nil); return }
        let view = OnboardingView { [weak self] in
            Settings.shared.onboardingComplete = true
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
        } startRunning: { [weak self] in
            if AppState.shared.ready == false { self?.startRunning() }
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "welcome"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 520, height: 560))
        window.center()
        onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

}

struct GateView: View {
    let reason: SystemLanguageModel.Availability.UnavailableReason

    private var message: String {
        switch reason {
        case .deviceNotEligible: "This Mac cannot run Apple Intelligence."
        case .appleIntelligenceNotEnabled: "Turn on Apple Intelligence in System Settings, then reopen Type Me It."
        case .modelNotReady: "Apple Intelligence is still downloading. Try again in a few minutes."
        @unknown default: "Apple Intelligence is not available right now."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Type Me It needs Apple Intelligence").font(.title2.weight(.semibold))
            Text(message).frame(maxWidth: 380, alignment: .leading)
            HStack {
                if case .appleIntelligenceNotEnabled = reason {
                    Button("Open System Settings") { NSWorkspace.shared.open(SecureInput.appleIntelligenceSettingsURL) }
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
