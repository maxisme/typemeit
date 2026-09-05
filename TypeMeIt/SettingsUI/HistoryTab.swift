import SwiftUI

struct HistoryTab: View {
    @State private var store = Store.shared
    @State private var settings = Settings.shared
    @State private var player = RecordingPlayer.shared
    @State private var search = ""
    @State private var expanded: Set<UUID> = []
    @State private var selected: Set<UUID> = []
    @State private var confirmDeleteAll = false

    private var filtered: [HistoryEntry] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let all = store.history.reversed()
        return q.isEmpty ? Array(all) : all.filter { $0.displayText.lowercased().contains(q) || $0.transcript.lowercased().contains(q) }
    }

    private var groups: [(title: String, entries: [HistoryEntry])] {
        let cal = Calendar.current
        var out: [(String, [HistoryEntry])] = []
        for e in filtered {
            let title: String
            if cal.isDateInToday(e.timestamp) { title = "today" }
            else if cal.isDateInYesterday(e.timestamp) { title = "yesterday" }
            else { title = e.timestamp.formatted(.dateTime.day().month(.wide)).lowercased() }
            if let last = out.last, last.0 == title { out[out.count - 1].1.append(e) } else { out.append((title, [e])) }
        }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image("akar-search").resizable().frame(width: 13, height: 13).foregroundStyle(DesignTokens.Colors.ink3)
                            TextField("search", text: $search).textFieldStyle(.plain)
                        }
                        .padding(.horizontal, 8).frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(DesignTokens.Colors.paperRaised))
                        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).strokeBorder(DesignTokens.Colors.ruleControl, lineWidth: 0.5))
                        Text("\(store.history.count) dictations")
                            .font(.system(size: 11).monospaced()).foregroundStyle(DesignTokens.Colors.ink2)
                        if !selected.isEmpty {
                            Button("delete \(selected.count)") { store.delete(ids: selected); selected = [] }
                                .buttonStyle(InkButtonStyle())
                        }
                        Button("delete all") { confirmDeleteAll = true }
                            .buttonStyle(InkButtonStyle())
                            .disabled(store.history.isEmpty)
                            .confirmationDialog("Delete all \(store.history.count) dictations?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                                Button("Delete All", role: .destructive) { store.deleteAllHistory(); selected = [] }
                            } message: { Text("This cannot be undone.") }
                    }
                    if groups.isEmpty {
                        Text(store.history.isEmpty ? "nothing yet" : "no matches")
                            .foregroundStyle(DesignTokens.Colors.ink2).frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                    ForEach(groups, id: \.title) { group in
                        SettingsGroup(title: group.title) {
                            ForEach(Array(group.entries.enumerated()), id: \.element.id) { i, e in
                                row(e, last: i == group.entries.count - 1)
                            }
                        }
                    }
                }
                .padding(20)
            }
            RowRule()
            VStack(spacing: 0) {
                SettingsRow(label: "keep") {
                    Picker("", selection: Binding(get: { settings.historyLimit }, set: { settings.historyLimit = $0; store.prune(limit: $0) })) {
                        ForEach([100, 250, 500, 1000, 2000, 5000], id: \.self) { Text("the last \($0) dictations").tag($0) }
                        Text("everything · never delete").tag(0)
                        Text("nothing · never keep").tag(-1)
                    }.labelsHidden().fixedSize()
                }
                SettingsRow(label: "keep the audio", subtitle: "about 120 KB a minute, deleted with the dictation", last: true) {
                    Toggle("", isOn: $settings.keepRecordings).toggleStyle(.switch).labelsHidden()
                        .disabled(settings.historyLimit < 0)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func row(_ e: HistoryEntry, last: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                selectToggle(e.id)
                Text(e.timestamp.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()))
                    .font(.system(size: 11).monospaced()).foregroundStyle(DesignTokens.Colors.ink2).frame(width: 44, alignment: .leading).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(e.displayText).font(.system(size: 13)).textSelection(.enabled)
                    HStack(spacing: 6) {
                        if e.edited != nil {
                            Text("edited").font(.system(size: 10).monospaced()).foregroundStyle(DesignTokens.Colors.ink2)
                                .padding(.horizontal, 5).padding(.vertical, 1).background(Rectangle().fill(DesignTokens.Colors.inkA08))
                        }
                        if let app = e.appName { Text(app.lowercased()).font(.system(size: 10)).foregroundStyle(DesignTokens.Colors.ink3) }
                    }
                    telemetry(e)
                    if expanded.contains(e.id), e.transcript != e.displayText {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("heard").font(.system(size: 10).monospaced()).foregroundStyle(DesignTokens.Colors.ink2)
                            Text(e.transcript).font(.system(size: 12)).foregroundStyle(DesignTokens.Colors.ink2).textSelection(.enabled)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(Rectangle().fill(DesignTokens.Colors.inkA04))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { if expanded.contains(e.id) { expanded.remove(e.id) } else { expanded.insert(e.id) } }
                HStack(spacing: 4) {
                    if e.recordingFile != nil {
                        let on = player.playing == e.id
                        iconButton(on ? "akar-stop" : "akar-play", on ? "stop" : "play the audio") { player.toggle(e) }
                    }
                    iconButton("akar-copy", "copy") { Output.copyToClipboard(e.displayText) }
                    iconButton("akar-trash-can", "delete") { store.delete(id: e.id) }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            if !last { RowRule() }
        }
    }

    /// Stage timings, monospaced and always visible.
    @ViewBuilder
    private func telemetry(_ e: HistoryEntry) -> some View {
        HStack(spacing: 0) {
            stat("asr", e.transcribeMs.map { "\($0)ms" } ?? "n/a")
            if let ms = e.transcribeMs, let audio = e.durationMs, audio > 0 {
                Text("  rtf=" + String(format: "%.2fx", Double(ms) / Double(audio)))
            }
            Text("  │  ")
            stat("llm", e.postProcessRequested ? (e.postProcessMs.map { "\($0)ms" } ?? "n/a") : "off")
            if e.postProcessRequested, e.postProcessMs != nil {
                Text("  " + (e.postProcessed == nil ? "→fallback" : "→applied"))
            }
            Text("  │  ")
            let total = (e.transcribeMs ?? 0) + (e.postProcessMs ?? 0)
            stat("total", e.transcribeMs == nil ? "n/a" : "\(total)ms")
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(DesignTokens.Colors.ink2)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Rectangle().fill(DesignTokens.Colors.inkA04))
        .textSelection(.enabled)
    }

    private func stat(_ key: String, _ value: String) -> some View {
        HStack(spacing: 0) {
            Text(key + "=").foregroundStyle(DesignTokens.Colors.ink3)
            Text(value)
        }
    }

    /// A hairline square that fills with ink when the row is selected.
    private func selectToggle(_ id: UUID) -> some View {
        let on = selected.contains(id)
        return Button {
            if on { selected.remove(id) } else { selected.insert(id) }
        } label: {
            ZStack {
                Rectangle().fill(on ? DesignTokens.Colors.ink : .clear)
                    .overlay(Rectangle().strokeBorder(on ? DesignTokens.Colors.ink : DesignTokens.Colors.ruleControl, lineWidth: DesignTokens.hairline))
                    .frame(width: 12, height: 12)
                if on { Image("akar-check").resizable().frame(width: 8, height: 8).foregroundStyle(DesignTokens.Colors.onSlab) }
            }
            .frame(width: 16, height: 16).padding(.top, 2)
        }
        .buttonStyle(.plain)
        .help(on ? "deselect" : "select")
    }

    private func iconButton(_ image: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(image).resizable().frame(width: 14, height: 14)
                .foregroundStyle(DesignTokens.Colors.ink2)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
