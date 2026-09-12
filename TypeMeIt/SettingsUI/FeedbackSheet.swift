import SwiftUI

/// Issue text typed for a dictation, kept for the session so a second report
/// on the same entry starts from the first.
@MainActor
@Observable
final class FeedbackDrafts {
    static let shared = FeedbackDrafts()
    var issues: [UUID: String] = [:]
}

/// Reports one history entry to typeme.it: the issue the user types, the
/// entry, the settings, the app and machine, and the audio if there is any
/// and the toggle is left on.
struct FeedbackSheet: View {
    let entry: HistoryEntry
    @Environment(\.dismiss) private var dismiss
    @State private var drafts = FeedbackDrafts.shared
    @State private var includeAudio = true
    @State private var state: Progress = .idle

    enum Progress: Equatable { case idle, sending, sent(String), failed(String) }

    private var issue: Binding<String> {
        Binding(get: { drafts.issues[entry.id] ?? "" }, set: { drafts.issues[entry.id] = $0 })
    }

    private var canSend: Bool {
        !issue.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && state != .sending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("report").font(DesignTokens.Fonts.label.weight(.regular).monospaced()).foregroundStyle(DesignTokens.Colors.ink2)
            Text(entry.displayText)
                .font(.system(size: 12)).foregroundStyle(DesignTokens.Colors.ink2)
                .lineLimit(4).frame(maxWidth: .infinity, alignment: .leading)
                .padding(8).background(Rectangle().fill(DesignTokens.Colors.inkA04))
            TextEditor(text: issue)
                .font(.system(size: 13)).scrollContentBackground(.hidden)
                .frame(height: 90).padding(6)
                .overlay(Rectangle().strokeBorder(DesignTokens.Colors.ruleControl, lineWidth: DesignTokens.hairline))
                .overlay(alignment: .topLeading) {
                    if issue.wrappedValue.isEmpty {
                        Text("what went wrong").foregroundStyle(DesignTokens.Colors.ink3).padding(.horizontal, 11).padding(.top, 6).allowsHitTesting(false)
                    }
                }
            if entry.recordingFile != nil {
                Toggle("send the audio", isOn: $includeAudio).toggleStyle(.checkbox).font(DesignTokens.Fonts.ui)
            }
            Text(note).font(.system(size: 11)).foregroundStyle(DesignTokens.Colors.ink2)
            HStack {
                Text(status).font(.system(size: 11).monospaced()).foregroundStyle(DesignTokens.Colors.ink2)
                Spacer()
                Button("cancel") { dismiss() }.buttonStyle(InkButtonStyle(quiet: true)).keyboardShortcut(.cancelAction)
                Button(state == .sending ? "sending" : "send") { Task { await send() } }
                    .buttonStyle(InkButtonStyle(primary: true)).disabled(!canSend).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(DesignTokens.Colors.paper)
        .onAppear { if entry.reportId != nil { state = .sent(entry.reportId!) } }
    }

    private var note: String {
        FeedbackClient.key == nil
            ? "this build has no feedback key"
            : "sends the text, your settings, the app version and your mac's model to typeme.it. kept 30 days."
    }

    private var status: String {
        switch state {
        case .idle, .sending: ""
        case .sent(let id): "sent · \(id.suffix(8))"
        case .failed(let why): "failed · \(why)"
        }
    }

    private func send() async {
        state = .sending
        let audio = includeAudio ? entry.recordingFile.flatMap { try? Data(contentsOf: RecordingArchive.url(for: $0)) } : nil
        let report = FeedbackReport(
            issue: issue.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines),
            previousId: entry.reportId,
            app: FeedbackReport.app(),
            dictation: FeedbackReport.dictation(entry),
            settings: FeedbackReport.settings(Settings.shared, learnedWords: Store.shared.learned.count),
            audio: audio?.base64EncodedString())
        do {
            let id = try await FeedbackClient.send(report)
            Store.shared.setReportId(id: entry.id, reportId: id)
            state = .sent(id)
            Log.app.info("Feedback sent: \(id)")
        } catch let f as FeedbackClient.Failure {
            state = .failed(describe(f))
            Log.app.error("Feedback failed: \(describe(f))")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func describe(_ f: FeedbackClient.Failure) -> String {
        switch f {
        case .noKey: "no key"
        case .tooLarge: "too large"
        case .status(let s): "server said \(s)"
        case .transport(let m): m
        }
    }
}
