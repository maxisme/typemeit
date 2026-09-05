import SwiftUI

enum SettingsTab: String, CaseIterable {
    case insights, settings, cleanup, history

    var icon: String {
        switch self {
        case .insights: "akar-statistic-up"
        case .settings: "akar-gear"
        case .cleanup: "akar-sparkles"
        case .history: "akar-history"
        }
    }
}

struct SettingsView: View {
    @State private var tab: SettingsTab? = .insights
    @State private var appState = AppState.shared

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 2) {
                Image(nsImage: MenuBarIconRenderer.mark(side: 40))
                    .resizable()
                    .frame(width: 40, height: 40)
                    .padding(.leading, 6)
                    .padding(.bottom, 8)
                ForEach(SettingsTab.allCases, id: \.self) { t in
                    let on = t == tab
                    Button { tab = t } label: {
                        HStack(spacing: 8) {
                            Image(t.icon).resizable().frame(width: 14, height: 14)
                            Text(t.rawValue).font(DesignTokens.Fonts.ui.monospaced().weight(.semibold))
                        }
                            .foregroundStyle(on ? DesignTokens.Colors.ink : DesignTokens.Colors.ink2)
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).fill(on ? DesignTokens.Colors.inkA08 : Color.clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(10)
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 220)
        } detail: {
            Group {
                switch tab ?? .insights {
                case .settings: MainSettingsTab()
                case .cleanup: CleanupTab()
                case .history: HistoryTab()
                case .insights: InsightsTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignTokens.Colors.paper)
            .navigationTitle("settings")
            .toolbar(removing: .title)
        }
        .tint(DesignTokens.Colors.ink)
        .frame(minWidth: 780, minHeight: 480)
        .onAppear(perform: takeRequestedTab)
        .onChange(of: appState.settingsTab) { _, _ in takeRequestedTab() }
    }

    private func takeRequestedTab() {
        guard let requested = appState.settingsTab else { return }
        tab = requested
        appState.settingsTab = nil
    }
}

/// The design system's button: mono label, ink outline, inverts when primary,
/// loses its outline when quiet. Disabled drops to ink-3 on a rule border.
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

        var body: some View {
            configuration.label
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(foreground)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(background)
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).strokeBorder(border, lineWidth: DesignTokens.hairline))
                .opacity(configuration.isPressed ? 0.6 : 1)
        }

        private var foreground: Color {
            if !enabled { return DesignTokens.Colors.ink3 }
            if primary { return DesignTokens.Colors.onSlab }
            return quiet ? DesignTokens.Colors.ink2 : DesignTokens.Colors.ink
        }

        private var background: Color {
            guard primary else { return .clear }
            return enabled ? DesignTokens.Colors.slab : DesignTokens.Colors.inkA12
        }

        private var border: Color {
            if primary || quiet { return .clear }
            return enabled ? DesignTokens.Colors.ink : DesignTokens.Colors.rule
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
                        Text(subtitle).font(.system(size: 11)).foregroundStyle(DesignTokens.Colors.ink2).frame(maxWidth: 400, alignment: .leading)
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
                        Picker("", selection: Binding(get: { settings.microphoneUID ?? "" }, set: { settings.microphoneUID = $0.isEmpty ? nil : $0; Pipeline.shared.applyMicrophoneSettings() })) {
                            Text("system default").tag("")
                            ForEach(devices) { d in Text(d.name).tag(d.id) }
                        }
                        .labelsHidden().fixedSize()
                        .onAppear { devices = AudioCapture.inputDevices() }
                    }
                    SettingsRow(label: "keep microphone open", subtitle: "faster start") {
                        Toggle("", isOn: Binding(get: { settings.alwaysOnMicrophone }, set: { settings.alwaysOnMicrophone = $0; Pipeline.shared.applyMicrophoneSettings() })).toggleStyle(.switch).labelsHidden()
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
                    SettingsRow(label: "cloud position") {
                        Picker("", selection: $settings.cloudPosition) {
                            ForEach(CloudPosition.allCases, id: \.self) { Text($0.label).tag($0) }
                        }.pickerStyle(.segmented).labelsHidden().fixedSize()
                    }
                    SettingsRow(label: "sounds") {
                        Toggle("", isOn: $settings.audioFeedback).toggleStyle(.switch).labelsHidden()
                    }
                    SettingsRow(label: "offer to copy when nothing is focused", last: true) {
                        Toggle("", isOn: $settings.copyPromptEnabled).toggleStyle(.switch).labelsHidden()
                    }
                }
                SettingsGroup(title: "paste") {
                    SettingsRow(label: "space after paste") {
                        Toggle("", isOn: $settings.appendTrailingSpace).toggleStyle(.switch).labelsHidden()
                    }
                    SettingsRow(label: "key after paste", last: !settings.autoSubmit) {
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
                    SettingsRow(label: "check for updates") {
                        Toggle("", isOn: Binding(get: { updates.automaticallyChecks }, set: { updates.automaticallyChecks = $0 })).toggleStyle(.switch).labelsHidden()
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
                    SettingsRow(label: "version \(AppVersion.current)", subtitle: "parakeet 0.6b · apple intelligence") {
                        Button("check now") { updates.checkForUpdates() }
                            .buttonStyle(InkButtonStyle())
                            .disabled(!updates.canCheck)
                    }
                    SettingsRow(label: "website", last: true) {
                        Link("typeme.it", destination: Fixed.websiteURL)
                            .font(.system(size: 12).monospaced()).foregroundStyle(DesignTokens.Colors.ink).underline()
                    }
                }
            }
            .padding(20)
        }
    }
}

struct CleanupTab: View {
    @State private var settings = Settings.shared
    @State private var store = Store.shared
    @State private var newWord = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsGroup(title: "clean-up") {
                    SettingsRow(label: "clean up with apple intelligence", subtitle: "on device") {
                        Toggle("", isOn: $settings.postProcessingEnabled).toggleStyle(.switch).labelsHidden()
                    }
                    SettingsRow(label: "learn from corrections", last: true) {
                        Toggle("", isOn: $settings.learnFromCorrections).toggleStyle(.switch).labelsHidden()
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
                                        }.buttonStyle(.plain).foregroundStyle(DesignTokens.Colors.ink2)
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
                            .onSubmit { settings.addCustomWord(newWord); newWord = "" }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                    }
                }
            }
            .padding(20)
        }
    }
}

/// A full-width row of resting puffs, one in each colour, each showing its
/// own smoke; the chosen one sits in an ink ring.
struct CloudColorPalette: View {
    @Binding var selection: CloudColor

    /// The cell each puff sits in, and the larger square it is drawn in, so
    /// the cloud fills the cell rather than resting a quarter of the way
    /// across it.
    private static let side: CGFloat = 64
    private static let drawn: CGFloat = 200

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(CloudColor.allCases.enumerated()), id: \.element) { i, c in
                let on = c == selection
                Button { selection = c } label: {
                    PuffView(level: 0, tint: Color(nsColor: c.color), timeOffset: Double(i) * 7.3)
                        .frame(width: CloudColorPalette.drawn, height: CloudColorPalette.drawn)
                        .frame(width: CloudColorPalette.side, height: CloudColorPalette.side)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(on ? DesignTokens.Colors.ink : .clear, lineWidth: 1.5).padding(2))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
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
                    Text("set shortcut").font(.system(size: 12).monospaced()).foregroundStyle(DesignTokens.Colors.ink2)
                        .frame(height: 22).padding(.horizontal, 8)
                        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).strokeBorder(DesignTokens.Colors.inkA20, lineWidth: 0.5))
                }
            }
            .buttonStyle(.plain)
            .help(recording ? "esc to cancel, ⌫ to clear" : "click, then press the keys")
            if combo != nil, !recording {
                Button { combo = nil } label: {
                    Image("akar-cross").resizable().frame(width: 8, height: 8)
                }
                .buttonStyle(.plain).foregroundStyle(DesignTokens.Colors.ink2)
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
