import FoundationModels
import SwiftUI

enum SettingsTab: String, CaseIterable {
    // The order the sidebar lists them in.
    case insights, intelligence, history, settings

    var icon: String {
        switch self {
        case .insights: "akar-statistic-up"
        case .settings: "akar-gear"
        case .intelligence: "akar-sparkles"
        case .history: "akar-history"
        }
    }
}

struct SettingsView: View {
    @State private var tab: SettingsTab? = .insights
    @State private var appState = AppState.shared

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                // Drawn as a template so it follows the appearance: the mark's
                // own ink is fixed at the time it is rendered.
                Image(nsImage: MenuBarIconRenderer.mark(side: 40))
                    .renderingMode(.template)
                    .resizable()
                    .foregroundStyle(DesignTokens.Colors.ink)
                    .frame(width: 40, height: 40)
                    .padding(.leading, 12)
                    .padding(.bottom, 14)
                ForEach(SettingsTab.allCases, id: \.self) { t in
                    SidebarItem(tab: t, selected: t == tab) { tab = t }
                }
                Spacer()
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(DesignTokens.Colors.paperSunk)
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(min: 180, ideal: 196, max: 240)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: (tab ?? .insights).rawValue)
                Group {
                    switch tab ?? .insights {
                    case .settings: MainSettingsTab()
                    case .intelligence: IntelligenceTab()
                    case .history: HistoryTab()
                    case .insights: InsightsTab()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignTokens.Colors.paper)
            .navigationTitle("settings")
            .toolbar(removing: .title)
        }
        .tint(DesignTokens.Colors.ink)
        .frame(minWidth: 780, minHeight: 700)
        .onAppear(perform: takeRequestedTab)
        .onChange(of: appState.settingsTab) { _, _ in takeRequestedTab() }
    }

    private func takeRequestedTab() {
        guard let requested = appState.settingsTab else { return }
        tab = requested
        appState.settingsTab = nil
    }
}

/// A sidebar choice. The slab runs the full width of the column so the
/// selection reads as a band in the window rather than a floating button, and
/// the pointer gets a light wash on the rest.
private struct SidebarItem: View {
    let tab: SettingsTab
    let selected: Bool
    let choose: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: choose) {
            HStack(spacing: 10) {
                Image(tab.icon).resizable().frame(width: 16, height: 16)
                Text(tab.rawValue).font(.system(size: 14, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(selected ? DesignTokens.Colors.onSlab : DesignTokens.Colors.ink2)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background(Rectangle().fill(fill))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var fill: Color {
        if selected { return DesignTokens.Colors.slab }
        return hovering ? DesignTokens.Colors.inkA08 : .clear
    }
}

/// The page's name, above the page's own scroll view, so content passes under
/// a hairline instead of running out at the window's edge.
private struct PageHeader: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.ink)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            Rectangle().fill(DesignTokens.Colors.rule).frame(height: DesignTokens.hairline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The design system's button: mono label, ink outline, inverts when primary,
/// loses its outline when quiet. Disabled drops to ink-3 on a rule border.
///
/// The pointer states are the ones `web/styles/app.css` gives `.btn-*`: an
/// outlined button takes an ink-a04 wash and a primary one eases off its slab
/// to ink-a88, and both go a step further while held. A disabled button
/// answers neither.
struct InkButtonStyle: ButtonStyle {
    var primary = false
    var quiet = false
    func makeBody(configuration: Configuration) -> some View {
        InkButtonLabel(configuration: configuration, primary: primary, quiet: quiet)
    }

    private struct InkButtonLabel: View {
        let configuration: Configuration
        let primary: Bool
        let quiet: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false
        private var hot: Bool { hovering && enabled }

        var body: some View {
            configuration.label
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(foreground)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).fill(background))
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).strokeBorder(border, lineWidth: DesignTokens.hairline))
                .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: DesignTokens.Duration.n1), value: hot)
        }

        private var foreground: Color {
            if !enabled { return DesignTokens.Colors.ink3 }
            if primary { return DesignTokens.Colors.onSlab }
            if quiet { return hot ? DesignTokens.Colors.ink : DesignTokens.Colors.ink2 }
            return DesignTokens.Colors.ink
        }

        private var background: Color {
            if primary {
                guard enabled else { return DesignTokens.Colors.inkA12 }
                if configuration.isPressed { return DesignTokens.Colors.inkA64 }
                return hot ? DesignTokens.Colors.inkA88 : DesignTokens.Colors.slab
            }
            guard enabled else { return .clear }
            if configuration.isPressed { return DesignTokens.Colors.inkA08 }
            return hot ? DesignTokens.Colors.inkA04 : .clear
        }

        private var border: Color {
            if primary || quiet { return .clear }
            return enabled ? DesignTokens.Colors.ink : DesignTokens.Colors.rule
        }
    }
}

/// The design system's plain button: no outline and no fill of its own, an
/// ink-a04 wash and full-strength ink under the pointer, a step darker while
/// held. It is what `.btn-quiet` is on the web, and it is the style for every
/// button that draws its own label — the icon buttons, the sidebar tabs, the
/// crosses that dismiss things.
struct QuietButtonStyle: ButtonStyle {
    /// A square target for icon buttons, so a 10pt glyph still gets something
    /// worth hovering. Nil leaves the label at the size it drew itself.
    var side: CGFloat?
    var radius: CGFloat = DesignTokens.Radius.sm
    /// A selected button is inverted outright and stops answering the pointer,
    /// being already the thing a click would ask for.
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        QuietButtonLabel(configuration: configuration, side: side, radius: radius, selected: selected)
    }

    private struct QuietButtonLabel: View {
        let configuration: Configuration
        let side: CGFloat?
        let radius: CGFloat
        let selected: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false
        private var hot: Bool { hovering && enabled && !selected }

        var body: some View {
            configuration.label
                .foregroundStyle(foreground)
                .frame(width: side, height: side)
                .background(RoundedRectangle(cornerRadius: radius).fill(background))
                .contentShape(RoundedRectangle(cornerRadius: radius))
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: DesignTokens.Duration.n1), value: hot)
        }

        private var foreground: Color {
            if selected { return DesignTokens.Colors.onSlab }
            if !enabled { return DesignTokens.Colors.ink3 }
            return hot ? DesignTokens.Colors.ink : DesignTokens.Colors.ink2
        }

        private var background: Color {
            if selected { return DesignTokens.Colors.slab }
            guard enabled else { return .clear }
            if configuration.isPressed { return DesignTokens.Colors.inkA08 }
            return hot ? DesignTokens.Colors.inkA04 : .clear
        }
    }
}

/// A square inset list with an ink border and a mono title above it.
struct SettingsGroup<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title.lowercased())
                    .font(DesignTokens.Fonts.label.weight(.regular).monospaced())
                    .foregroundStyle(DesignTokens.Colors.ink2)
            }
            VStack(spacing: 0) { content }
                .overlay(Rectangle().strokeBorder(DesignTokens.Colors.ink, lineWidth: DesignTokens.hairline))
        }
    }
}

/// Full-width hairline between rows.
struct RowRule: View {
    var body: some View { Rectangle().fill(DesignTokens.Colors.inkA20).frame(height: DesignTokens.hairline) }
}

extension SettingsRow {
    /// Parses a subtitle as markdown and underlines link runs, so any link in
    /// a subtitle carries the same underline the standalone `Link` rows do.
    /// Plain strings render unchanged; a malformed markdown string falls back
    /// to a plain AttributedString.
    static func subtitleAttributed(_ s: String) -> AttributedString {
        var attr = (try? AttributedString(markdown: s)) ?? AttributedString(s)
        for run in attr.runs where run.link != nil {
            attr[run.range].underlineStyle = .single
        }
        return attr
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
                    Text(label).font(DesignTokens.Fonts.ui.monospaced())
                    if let subtitle {
                        Text(SettingsRow.subtitleAttributed(subtitle)).font(.system(size: 11)).foregroundStyle(DesignTokens.Colors.ink2).tint(DesignTokens.Colors.ink).frame(maxWidth: 400, alignment: .leading)
                    }
                }
                Spacer()
                control
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            if !last { RowRule() }
        }
    }
}

struct MainSettingsTab: View {
    @State private var settings = Settings.shared
    @State private var updates = Updates.shared
    @State private var devices = AudioCapture.inputDevices()
    @State private var screenGranted = CGPreflightScreenCaptureAccess()
    /// The grant lands in System Settings, not in the app, so it is re-read
    /// while the window is up.
    private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    /// Screen Recording is the only permission that lets the app read the
    /// screen, so the row says what is read and what it asks for.
    private var backdropSubtitle: String {
        if settings.cloudMatchesBackdrop, !screenGranted { return "needs screen recording permissions" }
        return "reads a few pixels under the cloud - needs screen recording permissions"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsGroup(title: "shortcuts") {
                    SettingsRow(label: "hold to talk") { Keycap("fn") }
                    SettingsRow(label: "pin", subtitle: "fn again to finish") { Keycap("space") }
                    SettingsRow(label: "cancel") { Keycap("esc") }
                    SettingsRow(label: "copy last transcript", subtitle: "off until a shortcut is set", last: true) {
                        ShortcutRecorder(combo: $settings.copyLastShortcut)
                    }
                }
                SettingsGroup(title: "microphone") {
                    SettingsRow(label: "microphone") {
                        Picker("", selection: Binding(get: { settings.microphoneUID ?? "" }, set: { settings.microphoneUID = $0.isEmpty ? nil : $0 })) {
                            Text("system default").tag("")
                            ForEach(devices) { d in Text(d.name).tag(d.id) }
                        }
                        .labelsHidden().fixedSize()
                        .onAppear { devices = AudioCapture.inputDevices() }
                    }
                    SettingsRow(label: "mute other audio", last: true) {
                        Toggle("", isOn: $settings.muteWhileRecording).toggleStyle(.switch).labelsHidden()
                    }
                }
                SettingsGroup(title: "cloud") {
                    SettingsRow(label: "cloud colour", subtitle: "off, it is white or grey with the appearance") {
                        Toggle("", isOn: $settings.cloudColorEnabled).toggleStyle(.switch).labelsHidden()
                    }
                    if settings.cloudColorEnabled {
                        CloudColorPalette(selection: $settings.cloudColor)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                        RowRule()
                    }
                    SettingsRow(label: "match what is behind it", subtitle: backdropSubtitle) {
                        HStack(spacing: 8) {
                            if settings.cloudMatchesBackdrop, !screenGranted {
                                Button("system settings") { NSWorkspace.shared.open(SecureInput.screenRecordingSettingsURL) }.buttonStyle(InkButtonStyle())
                            }
                            Toggle("", isOn: Binding(get: { settings.cloudMatchesBackdrop }, set: { on in
                                settings.cloudMatchesBackdrop = on
                                if on, !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
                                screenGranted = CGPreflightScreenCaptureAccess()
                            })).toggleStyle(.switch).labelsHidden()
                        }
                    }
                    SettingsRow(label: "cloud position") {
                        Picker("", selection: $settings.cloudPosition) {
                            ForEach(CloudPosition.allCases, id: \.self) { Text($0.label).tag($0) }
                        }.pickerStyle(.segmented).labelsHidden().fixedSize()
                    }
                    SettingsRow(label: "sounds", last: true) {
                        Toggle("", isOn: $settings.audioFeedback).toggleStyle(.switch).labelsHidden()
                    }
                }
                SettingsGroup(title: "typing") {
                    SettingsRow(label: "space after typing") {
                        Toggle("", isOn: $settings.appendTrailingSpace).toggleStyle(.switch).labelsHidden()
                    }
                    SettingsRow(label: "offer to copy when no text box is focused") {
                        Toggle("", isOn: $settings.copyPromptEnabled).toggleStyle(.switch).labelsHidden()
                    }
                    SettingsRow(label: "key after typing", last: !settings.autoSubmit) {
                        Toggle("", isOn: $settings.autoSubmit).toggleStyle(.switch).labelsHidden()
                    }
                    if settings.autoSubmit {
                        SettingsRow(label: "key", last: true) {
                            Picker("", selection: $settings.autoSubmitKey) {
                                ForEach(AutoSubmitKey.allCases, id: \.self) { Text($0.label).tag($0) }
                            }.labelsHidden().fixedSize()
                        }
                    }
                }
                SettingsGroup(title: "app") {
                    SettingsRow(label: "open at login") {
                        Toggle("", isOn: Binding(get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0; AppDelegate.shared?.reconcileLaunchAtLogin() })).toggleStyle(.switch).labelsHidden()
                    }
                    SettingsRow(label: "ask before updating", subtitle: "otherwise it restarts itself when idle") {
                        Toggle("", isOn: Binding(get: { settings.askBeforeUpdating }, set: { settings.askBeforeUpdating = $0; Updates.shared.askPreferenceChanged() })).toggleStyle(.switch).labelsHidden()
                            .disabled(Updates.isDevBuild)
                    }
                    SettingsRow(label: "dock icon") {
                        Toggle("", isOn: Binding(get: { settings.showDockIcon }, set: { settings.showDockIcon = $0; AppDelegate.shared?.applyDockIcon() })).toggleStyle(.switch).labelsHidden()
                    }
                    SettingsRow(label: "appearance", subtitle: "the windows and the recording cloud", last: true) {
                        Picker("", selection: Binding(get: { settings.appearance }, set: { settings.appearance = $0; AppDelegate.shared?.applyAppearance() })) {
                            ForEach(Appearance.allCases, id: \.self) { Text($0.label).tag($0) }
                        }.labelsHidden().fixedSize()
                    }
                }
                SettingsGroup(title: "about") {
                    SettingsRow(label: "version \(AppVersion.current)", subtitle: "[parakeet 0.6b](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2) · [apple intelligence](https://www.apple.com/apple-intelligence/)") {
                        updateStatus
                    }
                    SettingsRow(label: "website", last: true) {
                        Link("typeme.it", destination: Fixed.websiteURL)
                            .font(.system(size: 12).monospaced()).foregroundStyle(DesignTokens.Colors.ink).underline()
                    }
                }
            }
            .padding(20)
        }
        .onReceive(poll) { _ in screenGranted = CGPreflightScreenCaptureAccess() }
    }

    /// Where the background update check got to. There is no button to check;
    /// the only action is installing a version that is already downloaded.
    @ViewBuilder
    private var updateStatus: some View {
        if Updates.isDevBuild {
            statusText("dev build · never updates")
        } else {
            switch updates.state {
            case .checking: statusText("checking for updates…")
            case .upToDate: statusText("the latest version")
            case .downloading(let v): statusText("downloading \(v)…")
            case .readyToInstall(let v):
                Button("install \(v)") { updates.install() }.buttonStyle(InkButtonStyle())
            case .installing: statusText("installing…")
            case .unreachable: statusText("can't reach the update server")
            case .downloadFailed(let v): statusText("couldn't download \(v) · trying again later")
            }
        }
    }

    private func statusText(_ text: String) -> some View {
        Text(text).font(.system(size: 11).monospaced()).foregroundStyle(DesignTokens.Colors.ink2)
    }
}

struct IntelligenceTab: View {
    @State private var settings = Settings.shared
    @State private var store = Store.shared
    @State private var newWord = ""
    @State private var availability = PostProcessor.availability
    @State private var verifier = VerifyCustomWord.shared
    @State private var player = RecordingPlayer.shared
    /// Apple Intelligence is switched in System Settings, not in the app, so
    /// it is re-read while the window is up.
    private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var modelAvailable: Bool {
        if case .available = availability { return true }
        return false
    }

    /// Why clean-up cannot run right now, or nil when it can.
    private var unavailableSubtitle: String? {
        guard case .unavailable(let reason) = availability else { return nil }
        switch reason {
        case .deviceNotEligible: return "this mac cannot run apple intelligence"
        case .appleIntelligenceNotEnabled: return "apple intelligence is off - turn it on in system settings to clean up and learn from corrections"
        case .modelNotReady: return "apple intelligence is still downloading - try again in a few minutes"
        @unknown default: return "apple intelligence is not available right now"
        }
    }

    /// Screen Recording is granted in System Settings too; the poll above re-reads it.
    @State private var screenGranted = CGPreflightScreenCaptureAccess()

    private var screenSubtitle: String {
        if settings.screenContextEnabled, !screenGranted { return "needs screen recording permissions, which are off" }
        return "spells names the way the window you dictate into does · needs screen recording"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsGroup(title: "clean-up") {
                    SettingsRow(label: "clean up with apple intelligence", subtitle: unavailableSubtitle ?? "on device") {
                        HStack(spacing: 8) {
                            if case .unavailable(.appleIntelligenceNotEnabled) = availability {
                                Button("system settings") { NSWorkspace.shared.open(SecureInput.appleIntelligenceSettingsURL) }.buttonStyle(InkButtonStyle())
                            }
                            Toggle("", isOn: $settings.postProcessingEnabled).toggleStyle(.switch).labelsHidden()
                                .disabled(!modelAvailable)
                        }
                    }
                    SettingsRow(label: "learn from corrections", subtitle: modelAvailable ? nil : "needs apple intelligence") {
                        Toggle("", isOn: $settings.learnFromCorrections).toggleStyle(.switch).labelsHidden()
                            .disabled(!modelAvailable)
                    }
                    SettingsRow(label: "read the screen", subtitle: screenSubtitle, last: true) {
                        HStack(spacing: 8) {
                            if settings.screenContextEnabled, !screenGranted {
                                Button("system settings") { NSWorkspace.shared.open(SecureInput.screenRecordingSettingsURL) }.buttonStyle(InkButtonStyle())
                            }
                            Toggle("", isOn: Binding(get: { settings.screenContextEnabled }, set: { on in
                                settings.screenContextEnabled = on
                                if on, !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
                                screenGranted = CGPreflightScreenCaptureAccess()
                            })).toggleStyle(.switch).labelsHidden()
                        }
                        .disabled(!settings.postProcessingEnabled)
                    }
                }
                SettingsGroup(title: "custom words") {
                    VStack(alignment: .leading, spacing: 0) {
                        if !settings.customWords.isEmpty {
                            FlowLayout(spacing: 6) {
                                ForEach(settings.customWords, id: \.self) { word in
                                    let learned = store.learnedRecord(for: word)
                                    HStack(spacing: 5) {
                                        if let learned {
                                            Image("akar-sparkles").resizable().frame(width: 10, height: 10)
                                                .foregroundStyle(DesignTokens.Colors.ink2)
                                                .help("learned from a correction: heard “\(learned.heard)”")
                                        }
                                        Text(word).font(.system(size: 12))
                                        Button {
                                            store.forgetLearned(word: word)
                                            settings.removeCustomWord(word)
                                        } label: {
                                            Image("akar-cross").resizable().frame(width: 8, height: 8)
                                        }
                                        .buttonStyle(QuietButtonStyle(side: 16, radius: DesignTokens.Radius.full))
                                        .help("forget \(word)")
                                    }
                                    .padding(.leading, learned == nil ? 9 : 7).padding(.trailing, 6)
                                    .frame(height: 22)
                                    .background(Capsule().fill(DesignTokens.Colors.inkA08))
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            RowRule()
                        }
                        TextField("add a word", text: $newWord)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addWordAndVerify() }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        if verifier.state != .idle {
                            RowRule()
                            verifyPanel
                                .padding(.horizontal, 12).padding(.vertical, 10)
                        }
                    }
                }
            }
            .padding(20)
        }
        .onAppear { availability = PostProcessor.availability }
        .onReceive(poll) { _ in availability = PostProcessor.availability; screenGranted = CGPreflightScreenCaptureAccess() }
    }

    private func addWordAndVerify() {
        let w = newWord.trimmingCharacters(in: .whitespaces)
        guard !w.isEmpty else { newWord = ""; return }
        let existing = settings.customWords
        settings.addCustomWord(w)
        newWord = ""
        // Only worth checking when the model can run. On other Macs the word
        // is added silently.
        if case .available = availability {
            verifier.run(for: w, existingWords: existing, history: store.history)
        }
    }

    @ViewBuilder
    private var verifyPanel: some View {
        switch verifier.state {
        case .idle: EmptyView()
        case .checking(let word, let scanned, let total):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("checking recent dictations for '\(word)' · \(scanned)/\(total)")
                    .font(.system(size: 11)).foregroundStyle(DesignTokens.Colors.ink2)
                Spacer()
                Button("stop") { verifier.clear() }.buttonStyle(InkButtonStyle(quiet: true))
            }
        case .done(let word, let matches, let scanned):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image("akar-sparkles").resizable().frame(width: 11, height: 11).foregroundStyle(DesignTokens.Colors.ink2)
                    Text(headline(for: word, matches: matches, scanned: scanned))
                        .font(.system(size: 11)).foregroundStyle(DesignTokens.Colors.ink2)
                    Spacer()
                    Button("dismiss") { verifier.clear() }.buttonStyle(InkButtonStyle(quiet: true))
                }
                ForEach(matches) { match in verifyRow(match) }
            }
        }
    }

    private func headline(for word: String, matches: [VerifyCustomWord.Match], scanned: Int) -> String {
        if matches.isEmpty { return "'\(word)' would not have changed the last \(scanned) dictations" }
        return "'\(word)' would have caught \(matches.count) of the last \(scanned) dictations"
    }

    @ViewBuilder
    private func verifyRow(_ match: VerifyCustomWord.Match) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(match.timestamp.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()))
                    .font(.system(size: 10).monospaced()).foregroundStyle(DesignTokens.Colors.ink3)
                Spacer()
                if match.recordingFile != nil, let entry = store.history.first(where: { $0.id == match.id }) {
                    let on = player.playing == match.id
                    Button {
                        player.toggle(entry)
                    } label: {
                        Image(on ? "akar-stop" : "akar-play").resizable().frame(width: 11, height: 11)
                    }
                    .buttonStyle(QuietButtonStyle(side: 20))
                    .help(on ? "stop" : "play the audio")
                }
            }
            Text(match.before).font(.system(size: 12))
                .foregroundStyle(DesignTokens.Colors.diffRemove).strikethrough()
            Text(match.after).font(.system(size: 12))
                .foregroundStyle(DesignTokens.Colors.diffAdd)
        }
        .padding(8)
        .background(Rectangle().fill(DesignTokens.Colors.inkA04))
    }
}

/// A full-width row of resting puffs, one in each colour, each showing its
/// own smoke; the chosen one is drawn larger.
struct CloudColorPalette: View {
    @Binding var selection: CloudColor
    @State private var hovered: CloudColor?

    /// The cell each puff sits in, and the larger square it is drawn in, so
    /// the cloud fills the cell rather than resting a quarter of the way
    /// across it.
    private static let side: CGFloat = 64
    private static let drawn: CGFloat = 200

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(CloudColor.allCases.enumerated()), id: \.element) { i, c in
                let on = c == selection
                // Chosen is 1.5; the pointer takes an unchosen puff part of
                // the way there, so the row answers before it is clicked.
                let scale = on ? 1.5 : (hovered == c ? 1.25 : 1.0)
                Button { selection = c } label: {
                    PuffView(level: 0, tint: Color(nsColor: c.color), timeOffset: Double(i) * 7.3)
                        .frame(width: CloudColorPalette.drawn, height: CloudColorPalette.drawn)
                        .frame(width: CloudColorPalette.side, height: CloudColorPalette.side)
                        .scaleEffect(scale)
                        .animation(.easeOut(duration: 0.18), value: scale)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? c : (hovered == c ? nil : hovered) }
                .help(c.label)
                .accessibilityLabel(c.label)
                .accessibilityAddTraits(on ? .isSelected : [])
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Shows a shortcut as keycaps, or "set shortcut" when there is none. A click
/// starts listening; the next key with ⌘, ⌥ or ⌃ becomes the shortcut, esc
/// gives up, and ⌫ on its own clears it. The × beside a set shortcut clears it too.
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo?
    @State private var recording = false
    @State private var monitor: Any?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button {
                recording ? stop() : start()
            } label: {
                if recording {
                    Text("press keys…").font(.system(size: 12).monospaced()).foregroundStyle(DesignTokens.Colors.ink2)
                        .frame(height: 22).padding(.horizontal, 8)
                        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).strokeBorder(DesignTokens.Colors.ink, style: StrokeStyle(lineWidth: 0.5, dash: [3, 2])))
                } else if let combo {
                    HStack(spacing: 4) { ForEach(combo.caps, id: \.self) { Keycap($0) } }
                } else {
                    // An empty outline is easy to read as furniture, so the
                    // pointer brings it up to a real edge and full ink.
                    Text("set shortcut").font(.system(size: 12).monospaced())
                        .foregroundStyle(hovering ? DesignTokens.Colors.ink : DesignTokens.Colors.ink2)
                        .frame(height: 22).padding(.horizontal, 8)
                        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).strokeBorder(hovering ? DesignTokens.Colors.ink : DesignTokens.Colors.inkA20, lineWidth: 0.5))
                }
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: DesignTokens.Duration.n1), value: hovering)
            .help(recording ? "esc to cancel, ⌫ to clear" : "click, then press the keys")
            if combo != nil, !recording {
                Button { combo = nil } label: {
                    Image("akar-cross").resizable().frame(width: 8, height: 8)
                }
                .buttonStyle(QuietButtonStyle(side: 18, radius: DesignTokens.Radius.full))
                .help("clear")
                .accessibilityLabel("clear shortcut")
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let bare = KeyCombo.Modifiers(event.modifierFlags).isEmpty
            if event.keyCode == 53, bare {  // esc
                stop()
            } else if event.keyCode == 51, bare {  // delete
                combo = nil
                stop()
            } else if let new = KeyCombo(event: event) {
                combo = new
                stop()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
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
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).fill(DesignTokens.Colors.paperRaised))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).strokeBorder(DesignTokens.Colors.inkA20, lineWidth: 0.5))
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
