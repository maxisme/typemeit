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
            Image(nsImage: appState.menuBarImage)
        }
        .menuBarExtraStyle(.menu)

        SwiftUI.Settings {
            SettingsView()
        }
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

    var menuBarImage: NSImage {
        let name: String
        if recording { name = "tray_recording" }
        else if transcribing { name = "tray_transcribing" }
        else if secureInputOn { name = "tray_idle_warning" }
        else { name = "tray_idle" }
        let image = NSImage(named: name) ?? NSImage(systemSymbolName: "waveform", accessibilityDescription: "TypeMeIt")!
        image.isTemplate = !secureInputOn
        image.size = NSSize(width: 18, height: 18)
        return image
    }
}

struct MenuContent: View {
    @State private var appState = AppState.shared
    @State private var updates = Updates.shared
    @State private var store = Store.shared

    var body: some View {
        Text("Type Me It \(Updates.currentVersion)")
        if appState.secureInputOn {
            Text("Secure Input is on in another app. Fn is unavailable.")
        }
        Divider()
        if Pipeline.shared.isBusy {
            Button("Cancel Recording") { Pipeline.shared.shortcuts.cancelFromOverlay() }
        }
        Button("Copy Last Transcript") { Pipeline.shared.copyLastTranscript() }
            .disabled(store.history.isEmpty)
        Divider()
        SettingsLink { Text("Settings…") }.keyboardShortcut(",", modifiers: .command)
        if let a = updates.available {
            Button("Update available: \(a.version)") { updates.open() }
        }
        Button("Check for Updates…") { AppDelegate.checkForUpdatesInteractively() }
        Divider()
        Button("Quit Type Me It") { NSApp.terminate(nil) }.keyboardShortcut("q", modifiers: .command)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var gateWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var secureInputTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = Settings.shared
        _ = Store.shared
        switch PostProcessor.availability {
        case .available:
            break
        case .unavailable(let reason):
            showGate(reason)
            return
        }
        if Settings.shared.onboardingComplete, ModelStore.isInstalled {
            startRunning()
        } else {
            showOnboarding()
            if ModelStore.isInstalled { Pipeline.shared.warmUp() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if onboardingWindow?.isVisible == true { onboardingWindow?.makeKeyAndOrderFront(nil) }
        return false
    }

    /// Launch sequence step 4 onwards.
    func startRunning() {
        Pipeline.shared.start()
        AppState.shared.ready = true
        observePipeline()
        secureInputTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in AppState.shared.secureInputOn = SecureInput.isEnabled }
        }
        Updates.shared.checkIfDue()
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
        } bringToFront: { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.onboardingWindow?.makeKeyAndOrderFront(nil)
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Welcome to Type Me It"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 520, height: 560))
        window.center()
        onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    static func checkForUpdatesInteractively() {
        Task { @MainActor in
            let result = await Updates.shared.check()
            let alert = NSAlert()
            if let result {
                alert.messageText = "Version \(result.version) is available"
                alert.informativeText = "You have \(Updates.currentVersion)."
                alert.addButton(withTitle: "Open Release Page")
                alert.addButton(withTitle: "Later")
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertFirstButtonReturn { Updates.shared.open() }
            } else {
                alert.messageText = "You're up to date"
                alert.informativeText = "Type Me It \(Updates.currentVersion) is the newest version."
                alert.addButton(withTitle: "OK")
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        }
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
