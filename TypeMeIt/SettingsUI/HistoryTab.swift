import SwiftUI

struct HistoryTab: View {
    @State private var store = Store.shared
    @State private var settings = Settings.shared
    @State private var search = ""
    @State private var expanded: Set<UUID> = []
    @State private var editing: UUID?
    @State private var editText = ""

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
            if cal.isDateInToday(e.timestamp) { title = "Today" }
            else if cal.isDateInYesterday(e.timestamp) { title = "Yesterday" }
            else { title = e.timestamp.formatted(.dateTime.day().month(.wide)) }
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
                            Image("akar-search").resizable().frame(width: 13, height: 13).foregroundStyle(.tertiary)
                            TextField("Search", text: $search).textFieldStyle(.plain)
                        }
                        .padding(.horizontal, 8).frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .controlBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.black.opacity(0.2), lineWidth: 0.5))
                        Text("\(store.history.count) dictations · cleaned and raw text, no audio")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if groups.isEmpty {
                        Text(store.history.isEmpty ? "Hold fn and speak. Your dictations will appear here." : "No matches.")
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 40)
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
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep the last").font(.system(size: 13))
                    Text("Each entry keeps the cleaned text and what was heard. Starred entries are always kept. Audio is never saved.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: Binding(get: { settings.historyLimit }, set: { settings.historyLimit = $0; store.prune(limit: $0) })) {
                    ForEach([100, 250, 500, 1000, 2000, 5000], id: \.self) { Text("\($0) dictations").tag($0) }
                }.labelsHidden().frame(width: 170)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func row(_ e: HistoryEntry, last: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Text(e.timestamp.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()))
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .leading).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    if editing == e.id {
                        TextEditor(text: $editText).font(.system(size: 13)).frame(minHeight: 60).scrollContentBackground(.hidden)
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 1))
                        HStack {
                            Button("Save") { saveEdit(e) }.keyboardShortcut(.defaultAction)
                            Button("Cancel") { editing = nil }
                        }.controlSize(.small)
                    } else {
                        Text(e.displayText).font(.system(size: 13)).textSelection(.enabled)
                    }
                    HStack(spacing: 6) {
                        if e.edited != nil {
                            Text("Edited").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                                .padding(.horizontal, 5).padding(.vertical, 1).background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.06)))
                        }
                        if let app = e.appName { Text(app).font(.system(size: 10)).foregroundStyle(.tertiary) }
                        if let ms = e.durationMs { Text(String(format: "%.0f s", Double(ms) / 1000)).font(.system(size: 10)).foregroundStyle(.tertiary) }
                    }
                    telemetry(e)
                    if expanded.contains(e.id), e.transcript != e.displayText {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("HEARD").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            Text(e.transcript).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.04)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { if expanded.contains(e.id) { expanded.remove(e.id) } else { expanded.insert(e.id) } }
                HStack(spacing: 4) {
                    iconButton("akar-copy", "Copy") { Output.copyToClipboard(e.displayText) }
                    iconButton("akar-pencil", "Edit") { editing = e.id; editText = e.displayText }
                    iconButton("akar-star", e.starred ? "Unstar" : "Star", filled: e.starred) { store.toggleStar(id: e.id) }
                    iconButton("akar-trash-can", "Delete") { store.delete(id: e.id) }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            if !last { Divider().padding(.leading, 12) }
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
        .foregroundStyle(Color(nsColor: .systemGreen).opacity(0.9))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.82)))
        .textSelection(.enabled)
    }

    private func stat(_ key: String, _ value: String) -> some View {
        HStack(spacing: 0) {
            Text(key + "=").foregroundStyle(Color(nsColor: .systemGreen).opacity(0.55))
            Text(value)
        }
    }

    private func iconButton(_ image: String, _ help: String, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(image).resizable().frame(width: 14, height: 14)
                .foregroundStyle(filled ? Color.accentColor : Color.secondary)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func saveEdit(_ e: HistoryEntry) {
        let new = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        editing = nil
        guard !new.isEmpty, new != e.displayText else { return }
        let original = e.displayText
        store.setEdited(id: e.id, text: new)
        LearningCoordinator.shared.learn(original: original, edited: new, source: "history", historyId: e.id)
    }
}
