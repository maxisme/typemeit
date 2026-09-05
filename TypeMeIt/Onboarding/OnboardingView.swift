import AVFoundation
import AppKit
import SwiftUI

struct OnboardingView: View {
    var finished: () -> Void
    var startRunning: () -> Void

    enum Step: Int, CaseIterable { case welcome, model, microphone, accessibility, fnKey, tryIt }

    @State private var step: Step = .welcome
    @State private var modelStore = ModelStore.shared
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var axGranted = AXIsProcessTrusted()
    @State private var listenGranted = CGPreflightListenEventAccess()
    @State private var fnOK = SecureInput.fnKeyDoesNothing
    @State private var dictated = false
    @State private var scratch = ""
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
                if step != .welcome {
                    Button("back") { move(to: Step(rawValue: step.rawValue - 1) ?? .welcome) }
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
    }

    private var title: String {
        switch step {
        case .welcome: "type me it"
        case .model: "speech model"
        case .microphone: "microphone"
        case .accessibility: "accessibility"
        case .fnKey: "the fn key"
        case .tryIt: "try it"
        }
    }

    private var body_: String {
        switch step {
        case .welcome: "hold the fn key, speak, let go. your words are transcribed on this mac, tidied up by apple intelligence, and typed where your cursor is. nothing leaves your computer."
        case .model: "parakeet runs on this mac. about 700 mb, downloaded once."
        case .microphone: "type me it needs the microphone to hear you."
        case .accessibility: "lets type me it type into the app you are using and notice when you correct a word."
        case .fnKey: "input monitoring lets type me it see fn while other apps are in front. macos also uses fn for its own shortcuts, so set “press 🌐 key to” to “do nothing” in system settings › keyboard. fn only works on apple keyboards."
        case .tryIt: "hold fn and say something. let go when you are done."
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome:
            SettingsGroup(title: "shortcuts") {
                SettingsRow(label: "hold to talk") { Keycap("fn") }
                SettingsRow(label: "pin", subtitle: "fn again to finish") { Keycap("space") }
                SettingsRow(label: "cancel", last: true) { Keycap("esc") }
            }
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
                    SettingsRow(label: "parakeet 0.6b", last: true) { Status("checking the download…") }
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
                AVCaptureDevice.requestAccess(for: .audio) { ok in Task { @MainActor in micGranted = ok } }
            }, settings: SecureInput.microphoneSettingsURL)
        case .accessibility:
            permission("accessibility", granted: axGranted, grant: {
                let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                axGranted = AXIsProcessTrustedWithOptions(opts)
            }, settings: SecureInput.accessibilitySettingsURL)
        case .fnKey:
            SettingsGroup {
                SettingsRow(label: "input monitoring") {
                    if listenGranted {
                        Status("granted", done: true)
                    } else {
                        HStack(spacing: 8) {
                            Button("system settings") { NSWorkspace.shared.open(SecureInput.inputMonitoringSettingsURL) }.buttonStyle(InkButtonStyle())
                            Button("grant") { listenGranted = CGRequestListenEventAccess() }.buttonStyle(InkButtonStyle(primary: true))
                        }
                    }
                }
                SettingsRow(label: "press 🌐 key to", last: true) {
                    if fnOK {
                        Status("do nothing", done: true)
                    } else {
                        HStack(spacing: 12) {
                            Status("a system action")
                            Button("keyboard settings") { NSWorkspace.shared.open(SecureInput.keyboardSettingsURL) }
                                .buttonStyle(InkButtonStyle())
                        }
                    }
                }
            }
        case .tryIt:
            VStack(alignment: .leading, spacing: 12) {
                if dictated, let last = store.newest {
                    Status("heard you", done: true)
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
                        .font(DesignTokens.Fonts.ui)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(DesignTokens.Colors.paperRaised))
                        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).strokeBorder(DesignTokens.Colors.ruleControl, lineWidth: 0.5))
                }
            }
        }
    }

    private func permission(_ label: String, granted: Bool, grant: @escaping () -> Void, settings: URL) -> some View {
        SettingsGroup {
            SettingsRow(label: label, last: true) {
                if granted {
                    Status("granted", done: true)
                } else {
                    HStack(spacing: 8) {
                        Button("system settings") { NSWorkspace.shared.open(settings) }.buttonStyle(InkButtonStyle())
                        Button("grant", action: grant).buttonStyle(InkButtonStyle(primary: true))
                    }
                }
            }
        }
    }

    private func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file).lowercased()
    }

    private var canContinue: Bool {
        switch step {
        case .welcome: true
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
