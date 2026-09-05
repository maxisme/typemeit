import AVFoundation
import AppKit
import SwiftUI

struct OnboardingView: View {
    var finished: () -> Void
    var startRunning: () -> Void
    var bringToFront: () -> Void

    enum Step: Int, CaseIterable { case welcome, model, microphone, accessibility, inputMonitoring, fnKey, tryIt }

    @State private var step: Step = .welcome
    @State private var modelStore = ModelStore.shared
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var axGranted = AXIsProcessTrusted()
    @State private var listenGranted = CGPreflightListenEventAccess()
    @State private var fnOK = SecureInput.fnKeyDoesNothing
    @State private var dictated = false
    @State private var warmedUp = false
    @State private var transcriberReady = false
    @State private var store = Store.shared
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title).font(.title.weight(.semibold))
            Text(body_).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            content
            Spacer()
            HStack {
                Text("Step \(step.rawValue + 1) of \(Step.allCases.count)").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button(step == .tryIt ? "Finish" : "Continue") { advance() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canContinue)
            }
        }
        .padding(28)
        .frame(width: 520, height: 560)
        .onReceive(poll) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        .onAppear { if modelStore.state == .installed, step == .welcome { } }
    }

    private var title: String {
        switch step {
        case .welcome: "Welcome to Type Me It"
        case .model: "Download the speech model"
        case .microphone: "Microphone"
        case .accessibility: "Accessibility"
        case .inputMonitoring: "Input Monitoring"
        case .fnKey: "The fn key"
        case .tryIt: "Try it"
        }
    }

    private var body_: String {
        switch step {
        case .welcome: "Hold the fn key, speak, let go. Your words are transcribed on this Mac, tidied up by Apple Intelligence, and typed wherever your cursor is. Nothing leaves your computer."
        case .model: "Type Me It uses the Parakeet speech model, about 700 MB, downloaded once."
        case .microphone: "Type Me It needs the microphone to hear you."
        case .accessibility: "Accessibility lets Type Me It type into the app you are using and notice when you correct a word."
        case .inputMonitoring: "Input Monitoring lets Type Me It see the fn key while other apps are in front."
        case .fnKey: "macOS uses the fn key for its own shortcuts. Set “Press 🌐 key to” to “Do Nothing” in System Settings › Keyboard so it is free for Type Me It. fn only works on Apple keyboards."
        case .tryIt: "Hold fn and say something. Let go when you are done."
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome:
            EmptyView()
        case .model:
            VStack(alignment: .leading, spacing: 10) {
                switch modelStore.state {
                case .installed:
                    Label("Model installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .downloading(let received, let total):
                    ProgressView(value: Double(received), total: Double(max(total, 1)))
                    Text("\(ByteCountFormatter.string(fromByteCount: received, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Cancel") { modelStore.cancel() }
                case .verifying:
                    ProgressView().controlSize(.small)
                    Text("Checking the download…").font(.caption).foregroundStyle(.secondary)
                case .failed(let message):
                    Text(message).foregroundStyle(.red).font(.callout)
                    Button("Retry") { modelStore.download() }
                case .missing:
                    Button("Download") { modelStore.download() }
                }
            }
        case .microphone:
            permissionRow(granted: micGranted, grant: {
                AVCaptureDevice.requestAccess(for: .audio) { ok in Task { @MainActor in micGranted = ok } }
            }, settings: SecureInput.microphoneSettingsURL)
        case .accessibility:
            permissionRow(granted: axGranted, grant: {
                let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                axGranted = AXIsProcessTrustedWithOptions(opts)
            }, settings: SecureInput.accessibilitySettingsURL)
        case .inputMonitoring:
            permissionRow(granted: listenGranted, grant: {
                listenGranted = CGRequestListenEventAccess()
            }, settings: SecureInput.inputMonitoringSettingsURL)
        case .fnKey:
            VStack(alignment: .leading, spacing: 10) {
                if fnOK {
                    Label("fn is set to Do Nothing", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Label("fn is still assigned to a system action", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Button("Open Keyboard Settings") { NSWorkspace.shared.open(SecureInput.keyboardSettingsURL) }
                }
            }
        case .tryIt:
            VStack(alignment: .leading, spacing: 10) {
                if dictated, let last = store.newest {
                    Label("Heard you", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(last.displayText).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.04)))
                } else if transcriberReady {
                    Label("Waiting for a dictation…", systemImage: "waveform").foregroundStyle(.secondary)
                    TextField("You can dictate into this field", text: .constant("")).textFieldStyle(.roundedBorder)
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading the speech model…").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func permissionRow(granted: Bool, grant: @escaping () -> Void, settings: URL) -> some View {
        HStack(spacing: 12) {
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Grant Permission", action: grant)
                Button("Open System Settings") { NSWorkspace.shared.open(settings) }
            }
        }
    }

    private var canContinue: Bool {
        switch step {
        case .welcome: true
        case .model: modelStore.state == .installed
        case .microphone: micGranted
        case .accessibility: axGranted
        case .inputMonitoring: listenGranted
        case .fnKey: fnOK
        case .tryIt: dictated
        }
    }

    private func advance() {
        if step == .tryIt { finished(); return }
        let next = Step(rawValue: step.rawValue + 1) ?? .tryIt
        if next == .model, modelStore.state == .missing { modelStore.download() }
        if modelStore.state == .installed, !warmedUp {
            warmedUp = true
            Pipeline.shared.warmUp()
        }
        if next == .tryIt { startRunning() }
        step = next
    }

    private func refresh() {
        let before = (micGranted, axGranted, listenGranted)
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        axGranted = AXIsProcessTrusted()
        listenGranted = CGPreflightListenEventAccess()
        fnOK = SecureInput.fnKeyDoesNothing
        // Granting happens in System Settings or a system alert, which leaves
        // this window behind them; come back as soon as the grant lands.
        if (!before.0 && micGranted) || (!before.1 && axGranted) || (!before.2 && listenGranted) { bringToFront() }
        if step == .tryIt {
            Task { transcriberReady = await Transcriber.shared.isLoaded }
            if let last = store.newest, Date().timeIntervalSince(last.timestamp) < 120 { dictated = true }
        }
    }
}
