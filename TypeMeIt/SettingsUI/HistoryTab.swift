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
                LazyVStack(alignment: .leading, spacing: 18) {
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
                            LazyVStack(spacing: 0) {
                                ForEach(Array(group.entries.enumerated()), id: \.element.id) { i, e in
                                    row(e, last: i == group.entries.count - 1)
                                }
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
                    if e.transcript != e.displayText {
                        if e.recordingFile != nil {
                            stages(e)
                        } else if expanded.contains(e.id) {
                            stage("heard", heard: e.transcript, typed: e.displayText)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { toggleExpanded(e.id) }
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

    private func toggleExpanded(_ id: UUID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    /// An accordion under rows that kept their audio and whose text changed
    /// after the engine heard it, so the original can be checked against the
    /// recording. Rows where nothing changed have nothing to show.
    @ViewBuilder
    private func stages(_ e: HistoryEntry) -> some View {
        let open = expanded.contains(e.id)
        VStack(alignment: .leading, spacing: 0) {
            Button { toggleExpanded(e.id) } label: {
                HStack(spacing: 5) {
                    Image("akar-chevron-down").resizable().frame(width: 10, height: 10)
                        .rotationEffect(.degrees(open ? 0 : -90))
                    Text("heard")
                }
                .font(.system(size: 10).monospaced()).foregroundStyle(DesignTokens.Colors.ink2)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(open ? "hide what was heard" : "show what was heard before clean-up")
            if open { stage(nil, heard: e.transcript, typed: e.displayText) }
        }
        .background(Rectangle().fill(DesignTokens.Colors.inkA04))
        .animation(.easeOut(duration: 0.15), value: open)
    }

    private func stage(_ label: String?, heard: String, typed: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let label { Text(label).font(.system(size: 10).monospaced()).foregroundStyle(DesignTokens.Colors.ink3) }
            TranscriptDiff(heard: heard, typed: typed)
        }
        .foregroundStyle(DesignTokens.Colors.ink2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Rectangle().fill(DesignTokens.Colors.inkA04))
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

/// What was heard against what was typed, a word at a time: words the
/// clean-up dropped are struck through in red, the words it put in their
/// place are green, and the rest reads as the transcript did.
private struct TranscriptDiff: View {
    let heard: String
    let typed: String

    private enum Change { case same, added, removed }

    var body: some View {
        text.font(.system(size: 12)).textSelection(.enabled)
    }

    private var text: Text {
        var out = Text("")
        for (i, run) in runs.enumerated() {
            if i > 0 { out = out + Text(" ") }
            switch run.change {
            case .same: out = out + Text(run.words).foregroundColor(DesignTokens.Colors.ink2)
            case .added: out = out + Text(run.words).foregroundColor(DesignTokens.Colors.diffAdd).fontWeight(.semibold)
            case .removed: out = out + Text(run.words).foregroundColor(DesignTokens.Colors.diffRemove).strikethrough()
            }
        }
        return out
    }

    /// The two texts merged back into one reading order. Removals are offsets
    /// into what was heard and insertions offsets into what was typed, so the
    /// two walks advance together and every word lands once.
    private var runs: [(change: Change, words: String)] {
        let old = heard.split(whereSeparator: \.isWhitespace).map(String.init)
        let new = typed.split(whereSeparator: \.isWhitespace).map(String.init)
        var removed: Set<Int> = []
        var inserted: [Int: String] = [:]
        for change in new.difference(from: old) {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, let word, _): inserted[offset] = word
            }
        }
        var out: [(change: Change, words: String)] = []
        var o = 0, n = 0
        while o < old.count || n < new.count {
            if let word = inserted[n] { append(&out, .added, word); n += 1; continue }
            if o < old.count, removed.contains(o) { append(&out, .removed, old[o]); o += 1; continue }
            if o < old.count, n < new.count { append(&out, .same, new[n]); o += 1; n += 1; continue }
            break
        }
        return out
    }

    /// Consecutive words of the same kind are one run, so a whole phrase is
    /// struck through in one piece rather than word by word.
    private func append(_ out: inout [(change: Change, words: String)], _ change: Change, _ word: String) {
        if out.last?.change == change { out[out.count - 1].words += " " + word } else { out.append((change, word)) }
    }
}
