import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            InsightsTab().tabItem { Label("Insights", image: "akar-statistic-up") }
            GeneralTab().tabItem { Label("General", image: "akar-microphone") }
            TextTab().tabItem { Label("Text", image: "akar-text-align-left") }
            HistoryTab().tabItem { Label("History", image: "akar-clock") }
            AppTab().tabItem { Label("App", image: "akar-gear") }
        }
        .frame(width: 640)
        .frame(minHeight: 420)
    }
}

/// A grouped card with rows, in the System Settings style.
struct SettingsGroup<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            }
            VStack(spacing: 0) { content }
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
        }
    }
}

struct SettingsRow<Control: View>: View {
    var label: String
    var subtitle: String?
    var last = false
    @ViewBuilder var control: Control

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.system(size: 13))
                    if let subtitle {
                        Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: 400, alignment: .leading)
                    }
                }
                Spacer()
                control
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            if !last { Divider().padding(.leading, 12) }
        }
    }
}

struct GeneralTab: View {
    @State private var settings = Settings.shared
    @State private var devices = AudioCapture.inputDevices()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsGroup(title: "Shortcuts") {
                    SettingsRow(label: "Hold to talk", subtitle: "Recording runs while the key is held. A single tap does nothing.") { Keycap("fn") }
                    SettingsRow(label: "Pin while holding", subtitle: "Keeps recording after you let go of fn. Also on the pill. Press fn again to finish.") { Keycap("space") }
                    SettingsRow(label: "Cancel", last: true) { Keycap("esc") }
                }
                SettingsGroup(title: "Audio") {
                    SettingsRow(label: "Microphone") {
                        Picker("", selection: Binding(get: { settings.microphoneUID ?? "" }, set: { settings.microphoneUID = $0.isEmpty ? nil : $0; Pipeline.shared.applyMicrophoneSettings() })) {
                            Text("System default").tag("")
                            ForEach(devices) { d in Text(d.name).tag(d.id) }
                        }
                        .labelsHidden().frame(width: 220)
                        .onAppear { devices = AudioCapture.inputDevices() }
                    }
                    SettingsRow(label: "Keep microphone open", subtitle: "Starts recording faster. Uses a little more power.") {
                        Toggle("", isOn: Binding(get: { settings.alwaysOnMicrophone }, set: { settings.alwaysOnMicrophone = $0; Pipeline.shared.applyMicrophoneSettings() })).toggleStyle(.switch).labelsHidden()
                    }
                    SettingsRow(label: "Mute other audio while recording", last: true) {
                        Toggle("", isOn: $settings.muteWhileRecording).toggleStyle(.switch).labelsHidden()
                    }
                }
                SettingsGroup(title: "Feedback") {
                    SettingsRow(label: "Show recording cloud", subtitle: "A small cloud at the bottom of the screen.") {
                        Toggle("", isOn: $settings.overlayEnabled).toggleStyle(.switch).labelsHidden()
                    }
                    SettingsRow(label: "Sounds") {
                        Toggle("", isOn: $settings.audioFeedback).toggleStyle(.switch).labelsHidden()
                    }
                    SettingsRow(label: "Offer to copy when nothing is focused", subtitle: "Shown on the pill when there is no text field to paste into.", last: true) {
                        Toggle("", isOn: $settings.copyPromptEnabled).toggleStyle(.switch).labelsHidden()
                    }
                }
            }
            .padding(20)
        }
    }
}

struct Keycap: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5))
    }
}

struct TextTab: View {
    @State private var settings = Settings.shared
    @State private var newWord = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsGroup {
                    SettingsRow(label: "Clean up with Apple Intelligence", subtitle: "Fixes punctuation, numbers and currency on device. Nothing leaves your Mac.", last: true) {
                        Toggle("", isOn: $settings.postProcessingEnabled).toggleStyle(.switch).labelsHidden()
                    }
                }
                SettingsGroup {
                    SettingsRow(label: "Learn from my corrections", subtitle: "When you fix a word Type Me It got wrong, in History or in the app you pasted into, it remembers the spelling.", last: true) {
                        Toggle("", isOn: $settings.learnFromCorrections).toggleStyle(.switch).labelsHidden()
                    }
                }
                SettingsGroup(title: "Custom words") {
                    VStack(alignment: .leading, spacing: 0) {
                        if !settings.customWords.isEmpty {
                            FlowLayout(spacing: 6) {
                                ForEach(settings.customWords, id: \.self) { word in
                                    HStack(spacing: 5) {
                                        Text(word).font(.system(size: 12))
                                        Button { settings.removeCustomWord(word) } label: {
                                            Image("akar-cross").resizable().frame(width: 8, height: 8)
                                        }.buttonStyle(.plain).foregroundStyle(.secondary)
                                    }
                                    .padding(.leading, 9).padding(.trailing, 6)
                                    .frame(height: 22)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            Divider().padding(.leading, 12)
                        }
                        HStack(spacing: 8) {
                            TextField("Add a name or term", text: $newWord)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { settings.addCustomWord(newWord); newWord = "" }
                            Text("Return to add").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                    }
                }
                SettingsGroup(title: "Paste") {
                    SettingsRow(label: "Add a space after pasting") {
                        Toggle("", isOn: $settings.appendTrailingSpace).toggleStyle(.switch).labelsHidden()
                    }
                    SettingsRow(label: "Press a key after pasting", last: !settings.autoSubmit) {
                        Toggle("", isOn: $settings.autoSubmit).toggleStyle(.switch).labelsHidden()
                    }
                    if settings.autoSubmit {
                        SettingsRow(label: "Key", last: true) {
                            Picker("", selection: $settings.autoSubmitKey) {
                                ForEach(AutoSubmitKey.allCases, id: \.self) { Text($0.label).tag($0) }
                            }.labelsHidden().frame(width: 180)
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

/// Wraps its children onto as many lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct AppTab: View {
    @State private var settings = Settings.shared
    @State private var updates = Updates.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsGroup(title: "General") {
                    SettingsRow(label: "Open at login") {
                        Toggle("", isOn: Binding(get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0; (NSApp.delegate as? AppDelegate)?.reconcileLaunchAtLogin() })).toggleStyle(.switch).labelsHidden()
                    }
                    SettingsRow(label: "Check for updates automatically") {
                        Toggle("", isOn: Binding(get: { Updates.shared.automaticallyChecks }, set: { Updates.shared.automaticallyChecks = $0 })).toggleStyle(.switch).labelsHidden()
                    }
                    SettingsRow(label: "Check for updates now") {
                        Button("Check Now") { Updates.shared.checkForUpdates() }
                            .disabled(!updates.canCheck)
                    }
                    SettingsRow(label: "Website", last: true) {
                        Link("typeme.it", destination: URL(string: "https://typeme.it")!)
                    }
                }
                VStack(spacing: 2) {
                    Text("Type Me It \(AppVersion.current) · Parakeet 0.6B on device")
                    Text("Apple Intelligence available")
                }
                .font(.system(size: 11)).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
            }
            .padding(20)
        }
    }
}
