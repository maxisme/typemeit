import AVFoundation
import AppKit
import SwiftUI

struct OnboardingView: View {
    var finished: () -> Void
    var startRunning: () -> Void

    enum Step: Int, CaseIterable { case model, microphone, accessibility, fnKey, tryIt }

    /// Opens on the first step that is not yet satisfied, so a permission
    /// lost since the last launch (a reinstall, a signature change, a TCC
    /// reset) lands straight on its page.
    @State private var step: Step = OnboardingView.firstUnsatisfiedStep()
    @State private var modelStore = ModelStore.shared
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var axGranted = AXIsProcessTrusted()
    @State private var listenGranted = CGPreflightListenEventAccess()
    @State private var fnOK = SecureInput.fnKeyDoesNothing
    @State private var dictated = false
    /// Steps whose grant click did not produce a permission. macOS shows the
    /// prompt once per app, so the button on these steps opens System Settings.
    @State private var needsSettings: Set<Step> = []
    @State private var scratch = ""
    @FocusState private var scratchFocused: Bool
    @State private var store = Store.shared
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("step \(step.rawValue + 1) of \(Step.allCases.count)")
                    .font(DesignTokens.Fonts.micro.monospaced())
                    .foregroundStyle(DesignTokens.Colors.ink3)
                Text(title)
                    .font(DesignTokens.Fonts.display3)
                    .tracking(DesignTokens.Tracking.display3)
                    .foregroundStyle(DesignTokens.Colors.ink)
                Text(body_)
                    .font(DesignTokens.Fonts.body)
                    .foregroundStyle(DesignTokens.Colors.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
                .padding(.top, 24)
                .id(step)
                .transition(.opacity)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                StepDots(current: step.rawValue, count: Step.allCases.count)
                Spacer()
                if step != .model {
                    Button("back") { move(to: Step(rawValue: step.rawValue - 1) ?? .model) }
                        .buttonStyle(InkButtonStyle(quiet: true))
                }
                if step == .tryIt, !dictated {
                    Button("skip") { finished() }
                        .buttonStyle(InkButtonStyle(quiet: true))
                }
                Button(step == .tryIt ? "finish" : "continue") { advance() }
                    .buttonStyle(InkButtonStyle(primary: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canContinue)
            }
        }
        .padding(28)
        .frame(width: 520, height: 560)
        .background(DesignTokens.Colors.paper)
        .tint(DesignTokens.Colors.ink)
        .animation(.easeOut(duration: DesignTokens.Duration.n2), value: step)
        .onReceive(poll) { _ in refresh() }
        .onAppear { if step == .model, modelStore.state == .missing { modelStore.download() } }
        .onChange(of: canContinue) { _, ok in if ok { advanceWhenSettled() } }
    }

    private var title: String {
        switch step {
        case .model: "speech model"
        case .microphone: "microphone"
        case .accessibility: "accessibility"
        case .fnKey: "the fn key"
        case .tryIt: "try it"
        }
    }

    private var body_: String {
        switch step {
        case .model: "hold the fn key, speak, let go. your words are transcribed on this mac by parakeet, about 700 mb downloaded once, tidied up by apple intelligence, and typed where your cursor is. nothing leaves your computer."
        case .microphone: "type me it needs the microphone."
        case .accessibility: "lets type me it type into the app you are using and learn when you correct a word."
        case .fnKey: "input monitoring lets type me it see fn while other apps are in front. macos uses fn for a shortcut of its own, which is turned off in keyboard settings."
        case .tryIt: "hold fn and say something. let go when you are done."
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .model:
            SettingsGroup {
                switch modelStore.state {
                case .installed:
                    SettingsRow(label: "parakeet 0.6b", last: true) { Status("installed", done: true) }
                case .downloading(let received, let total):
                    SettingsRow(label: "parakeet 0.6b", subtitle: "\(bytes(received)) of \(bytes(total))") {
                        Button("cancel") { modelStore.cancel() }.buttonStyle(InkButtonStyle())
                    }
                    InkProgress(value: Double(received) / Double(max(total, 1)))
                        .padding(.horizontal, 12).padding(.vertical, 12)
                case .verifying:
                    SettingsRow(label: "parakeet 0.6b", last: true) { Status("checking the model…") }
                case .failed(let message):
                    SettingsRow(label: "parakeet 0.6b", subtitle: message.lowercased(), last: true) {
                        Button("retry") { modelStore.download() }.buttonStyle(InkButtonStyle(primary: true))
                    }
                case .missing:
                    SettingsRow(label: "parakeet 0.6b", last: true) {
                        Button("download") { modelStore.download() }.buttonStyle(InkButtonStyle(primary: true))
                    }
                }
            }
        case .microphone:
            permission("microphone", granted: micGranted, grant: {
                if AVCaptureDevice.authorizationStatus(for: .audio) == .denied { return false }
                AVCaptureDevice.requestAccess(for: .audio) { ok in Task { @MainActor in micGranted = ok } }
                return true
            }, missing: { AVCaptureDevice.authorizationStatus(for: .audio) != .authorized }, settings: SecureInput.microphoneSettingsURL)
        case .accessibility:
            permission("accessibility", granted: axGranted, grant: {
                let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                axGranted = AXIsProcessTrustedWithOptions(opts)
                return true
            }, missing: { !AXIsProcessTrusted() }, settings: SecureInput.accessibilitySettingsURL)
        case .fnKey:
            SettingsGroup {
                permissionRow("input monitoring", granted: listenGranted, grant: {
                    listenGranted = CGRequestListenEventAccess()
                    return true
                }, missing: { !CGPreflightListenEventAccess() }, settings: SecureInput.inputMonitoringSettingsURL, last: false)
                SettingsRow(label: "press 🌐 key to", subtitle: fnOK ? nil : "set it to “do nothing” to overwrite the macos defaults.", last: true) {
                    if fnOK {
                        Status("do nothing", done: true)
                    } else {
                        Button("keyboard settings") { NSWorkspace.shared.open(SecureInput.keyboardSettingsURL) }
                            .buttonStyle(InkButtonStyle(primary: true))
                    }
                }
            }
        case .tryIt:
            VStack(alignment: .leading, spacing: 12) {
                if dictated, let last = store.newest {
                    Status("typed!", done: true)
                    Text(last.displayText)
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.Colors.ink)
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Rectangle().fill(DesignTokens.Colors.inkA04))
                } else {
                    Status("waiting for a dictation…")
                    TextField("dictate into this field", text: $scratch)
                        .textFieldStyle(.plain)
                        .focused($scratchFocused)
                        .onAppear { scratchFocused = true }
                        .font(DesignTokens.Fonts.ui)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(DesignTokens.Colors.paperRaised))
                        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).strokeBorder(DesignTokens.Colors.ruleControl, lineWidth: 0.5))
                }
            }
        }
    }

    private func permission(_ label: String, granted: Bool, grant: @escaping () -> Bool, missing: @escaping () -> Bool, settings: URL) -> some View {
        SettingsGroup {
            permissionRow(label, granted: granted, grant: grant, missing: missing, settings: settings, last: true)
        }
    }

    /// One button. "grant" asks macOS for the permission; `grant` returns
    /// false when it already knows the prompt cannot appear. macOS shows the
    /// prompt once per app, so if a moment later the permission is still
    /// `missing` and this app is still active, meaning no dialog took the
    /// focus, the prompt was used up on an earlier launch: the button becomes
    /// "system settings" and opens the pane straight away.
    private func permissionRow(_ label: String, granted: Bool, grant: @escaping () -> Bool, missing: @escaping () -> Bool, settings: URL, last: Bool) -> some View {
        let current = step
        let viaSettings = needsSettings.contains(current)
        return SettingsRow(label: label, subtitle: viaSettings && !granted ? "macos did not ask, so you might need to turn it on in system settings" : nil, last: last) {
            if granted {
                Status("granted", done: true)
            } else if viaSettings {
                Button("system settings") { NSWorkspace.shared.open(settings) }.buttonStyle(InkButtonStyle(primary: true))
            } else {
                Button("grant") {
                    if !grant() { needsSettings.insert(current); NSWorkspace.shared.open(settings); return }
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.5))
                        refresh()
                        if step == current, missing(), NSApp.isActive {
                            needsSettings.insert(current)
                            NSWorkspace.shared.open(settings)
                        }
                    }
                }.buttonStyle(InkButtonStyle(primary: true))
            }
        }
    }

    private func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file).lowercased()
    }

    private var canContinue: Bool {
        switch step {
        case .model: modelStore.state == .installed
        case .microphone: micGranted
        case .accessibility: axGranted
        case .fnKey: listenGranted && fnOK
        case .tryIt: dictated
        }
    }

    private func advance() {
        if step == .tryIt { finished(); return }
        let next = Step(rawValue: step.rawValue + 1) ?? .tryIt
        if next == .model, modelStore.state == .missing { modelStore.download() }
        if next == .tryIt { startRunning() }
        move(to: next)
    }

    private func move(to next: Step) {
        step = next
    }

    /// A step whose requirement was just met moves on by itself, after a beat
    /// long enough to read the check. The try-it step waits for the button,
    /// and an arrival on an already-satisfied step does not fire here.
    private func advanceWhenSettled() {
        let current = step
        guard current != .tryIt else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(DesignTokens.Duration.n4))
            if step == current, canContinue { advance() }
        }
    }

    /// Every permission the app cannot run without.
    static var permissionsGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized && AXIsProcessTrusted() && CGPreflightListenEventAccess()
    }

    private static func firstUnsatisfiedStep() -> Step {
        guard Settings.shared.onboardingComplete, ModelStore.isInstalled else { return .model }
        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized { return .microphone }
        if !AXIsProcessTrusted() { return .accessibility }
        if !CGPreflightListenEventAccess() { return .fnKey }
        return .model
    }

    private func refresh() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        axGranted = AXIsProcessTrusted()
        listenGranted = CGPreflightListenEventAccess()
        fnOK = SecureInput.fnKeyDoesNothing
        if step == .tryIt, let last = store.newest, Date().timeIntervalSince(last.timestamp) < 120 { dictated = true }
    }
}

/// A mono status line. Done carries a check in ink; pending is ink-2 with no icon.
private struct Status: View {
    var text: String
    var done = false
    init(_ text: String, done: Bool = false) { self.text = text; self.done = done }

    var body: some View {
        HStack(spacing: 6) {
            if done {
                Image("akar-circle-check").resizable().frame(width: 13, height: 13)
            }
            Text(text).font(.system(size: 12).monospaced())
        }
        .foregroundStyle(done ? DesignTokens.Colors.ink : DesignTokens.Colors.ink2)
    }
}

/// A flat ink bar on an ink-a08 track, the same gauge insights draws.
private struct InkProgress: View {
    var value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(DesignTokens.Colors.inkA08)
                Rectangle().fill(DesignTokens.Colors.ink).frame(width: geo.size.width * min(1, max(0, value)))
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: DesignTokens.Duration.n2), value: value)
    }
}

/// One square per step: ink for the steps reached, ink-a08 for the rest.
private struct StepDots: View {
    var current: Int
    var count: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { i in
                Rectangle()
                    .fill(i <= current ? DesignTokens.Colors.ink : DesignTokens.Colors.inkA08)
                    .frame(width: 8, height: 8)
            }
        }
    }
}
