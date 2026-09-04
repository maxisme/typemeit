import SwiftUI

struct InsightsTab: View {
    @State private var store = Store.shared

    private var stats: InsightsStats {
        Insights.compute(store.history.map {
            InsightRow(timestamp: $0.timestamp, transcript: $0.transcript, postProcessed: $0.postProcessed,
                       postProcessRequested: $0.postProcessRequested, durationMs: $0.durationMs,
                       dictionaryFixes: $0.dictionaryFixes, appId: $0.appId, appName: $0.appName, windowTitle: $0.windowTitle)
        })
    }

    private static let typingWPM = 40.0
    private static let gaugeMax = 200.0
    private static let categoryColors: [UsageCategory: Color] = [
        .aiPrompts: Color(red: 0.04, green: 0.38, blue: 1.0), .workMessages: Color(red: 0.37, green: 0.36, blue: 0.9),
        .code: Color(red: 0.19, green: 0.69, blue: 0.78), .emails: Color(red: 1.0, green: 0.62, blue: 0.04),
        .documents: Color(red: 0.2, green: 0.78, blue: 0.35), .personalMessages: Color(red: 0.86, green: 0.35, blue: 0.58),
        .other: Color(white: 0.63),
    ]

    var body: some View {
        let s = stats
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    statCard("Words dictated", s.totalWords.formatted(), monthCaption(s))
                    wpmCard(s)
                    statCard("Fixes made by Type Me It", (s.dictionaryFixes + s.postProcessFixes).formatted(),
                             "\(s.dictionaryFixes.formatted()) dictionary · \(s.postProcessFixes.formatted()) Apple Intelligence")
                }
                HStack(alignment: .top, spacing: 12) {
                    SettingsGroup(title: "Where dictations go") { categories(s) }.frame(maxWidth: .infinity)
                    SettingsGroup(title: "Top apps · \(s.totalApps) used") { topApps(s) }.frame(width: 240)
                }
                SettingsGroup(title: s.currentStreak > 0 ? "\(s.currentStreak) day streak · longest \(s.longestStreak)" : "Streak · longest \(s.longestStreak)") {
                    calendar(s)
                }
            }
            .padding(20)
        }
    }

    private func monthCaption(_ s: InsightsStats) -> String {
        let delta: String
        if s.wordsPreviousMonth > 0 {
            let pct = Int((Double(s.wordsThisMonth - s.wordsPreviousMonth) / Double(s.wordsPreviousMonth) * 100).rounded())
            delta = (pct >= 0 ? "+" : "") + "\(pct)% this month"
        } else {
            delta = "\(s.wordsThisMonth.formatted()) this month"
        }
        return "\(delta) · \(s.totalDictations) dictations"
    }

    private func statCard(_ label: String, _ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 26, weight: .semibold)).monospacedDigit()
            Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
    }

    private func wpmCard(_ s: InsightsStats) -> some View {
        let wpm = s.wordsPerMinute ?? 0
        return VStack(alignment: .leading, spacing: 2) {
            Text("Words per minute").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Text(wpm > 0 ? "\(Int(wpm.rounded()))" : "–").font(.system(size: 26, weight: .semibold)).monospacedDigit()
            Text(wpm > 0 ? String(format: "%.1f× faster than typing", wpm / InsightsTab.typingWPM) : "No timed dictations yet")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.08)).frame(height: 6)
                    Capsule().fill(Color.accentColor).frame(width: geo.size.width * min(1, wpm / InsightsTab.gaugeMax), height: 6)
                    Rectangle().fill(Color.secondary).frame(width: 1.5, height: 12)
                        .offset(x: geo.size.width * (InsightsTab.typingWPM / InsightsTab.gaugeMax), y: 0)
                }
            }
            .frame(height: 12).padding(.top, 8)
            HStack { Text("typing 40"); Spacer(); Text("you \(Int(wpm.rounded()))") }.font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
    }

    private func categories(_ s: InsightsStats) -> some View {
        let total = max(1, s.categories.reduce(0) { $0 + $1.dictations })
        return VStack(alignment: .leading, spacing: 10) {
            if s.categories.isEmpty {
                Text("Dictate into a few apps and the breakdown appears here.").font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 2) {
                    ForEach(s.categories, id: \.category) { c in
                        Rectangle().fill(InsightsTab.categoryColors[c.category] ?? .gray)
                            .frame(width: max(2, 300 * CGFloat(c.dictations) / CGFloat(total)))
                    }
                }
                .frame(height: 10).clipShape(Capsule())
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                    ForEach(s.categories, id: \.category) { c in
                        HStack(spacing: 6) {
                            Circle().fill(InsightsTab.categoryColors[c.category] ?? .gray).frame(width: 8, height: 8)
                            Text(c.category.displayName).font(.system(size: 12))
                            Spacer()
                            Text("\(Int((Double(c.dictations) / Double(total) * 100).rounded()))%").font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Text("From the app you dictated into. Browser tabs and terminals are sorted by window title.")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(14)
    }

    private func topApps(_ s: InsightsStats) -> some View {
        VStack(spacing: 0) {
            if s.topApps.isEmpty { Text("No apps yet").font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 8) }
            ForEach(Array(s.topApps.enumerated()), id: \.element.name) { i, a in
                HStack {
                    Text(a.name).font(.system(size: 12)).lineLimit(1)
                    Spacer()
                    Text("\(a.words.formatted()) words").font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
                }
                .padding(.vertical, 5)
                if i < s.topApps.count - 1 { Divider() }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private func calendar(_ s: InsightsStats) -> some View {
        let byDate = Dictionary(uniqueKeysWithValues: s.activity.map { ($0.date, $0.dictations) })
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weeks = 16
        let start = cal.date(byAdding: .day, value: -(weeks * 7 - 1), to: today)!
        let maxCount = max(1, s.activity.map(\.dictations).max() ?? 1)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 3) {
                ForEach(0..<weeks, id: \.self) { w in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { d in
                            let date = cal.date(byAdding: .day, value: w * 7 + d, to: start)!
                            let n = byDate[f.string(from: date)] ?? 0
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(Color.accentColor.opacity(n == 0 ? 0.08 : 0.3 + 0.7 * Double(n) / Double(maxCount)))
                                .frame(width: 11, height: 11)
                        }
                    }
                }
            }
            HStack(spacing: 4) {
                Spacer()
                Text("Less").font(.system(size: 10)).foregroundStyle(.tertiary)
                ForEach([0.08, 0.3, 0.55, 0.8, 1.0], id: \.self) { o in RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(o)).frame(width: 9, height: 9) }
                Text("More").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .padding(14)
    }
}
