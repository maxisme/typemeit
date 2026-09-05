import SwiftUI

struct InsightsTab: View {
    @State private var store = Store.shared
    @State private var whereHeight: CGFloat = 0

    private var stats: InsightsStats {
        Insights.compute(store.history.map {
            InsightRow(timestamp: $0.timestamp, transcript: $0.transcript, postProcessed: $0.postProcessed,
                       postProcessRequested: $0.postProcessRequested, durationMs: $0.durationMs,
                       dictionaryFixes: $0.dictionaryFixes, appId: $0.appId, appName: $0.appName, windowTitle: $0.windowTitle)
        })
    }

    private static let typingWPM = 40.0
    private static let gaugeMax = 200.0
    /// Tonal ramp of ink, darkest for the largest share. Indexed by rank.
    private static let ramp: [Color] = [
        DesignTokens.Colors.ink, DesignTokens.Colors.inkA64, DesignTokens.Colors.inkA48, DesignTokens.Colors.inkA32,
        DesignTokens.Colors.inkA20, DesignTokens.Colors.inkA12, DesignTokens.Colors.inkA08, DesignTokens.Colors.inkA04,
    ]
    private static func tone(_ rank: Int) -> Color { ramp[min(rank, ramp.count - 1)] }

    var body: some View {
        let s = stats
        // Not a scroll view: the page fits, and an outer scroll fought the
        // apps list's own.
        VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    statCard("words dictated", s.totalWords.formatted(), monthCaption(s))
                    wpmCard(s)
                    statCard("fixes", (s.dictionaryFixes + s.postProcessFixes).formatted(),
                             "\(s.dictionaryFixes.formatted()) words · \(s.postProcessFixes.formatted()) clean-ups")
                }
                .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 12) {
                    SettingsGroup(title: "where") { categories(s) }
                        .frame(maxWidth: .infinity)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { whereHeight = $0 }
                    SettingsGroup(title: "apps · \(s.totalApps)") { topApps(s) }
                        .frame(width: 240)
                        .frame(height: whereHeight > 0 ? whereHeight : nil, alignment: .top)
                }
                SettingsGroup(title: s.currentStreak > 0 ? "\(s.currentStreak) day streak · longest \(s.longestStreak)" : "streak · longest \(s.longestStreak)") {
                    calendar(s)
                }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
            Text(label).font(.system(size: 11).monospaced()).foregroundStyle(DesignTokens.Colors.ink2)
            Text(value).font(.system(size: 26, weight: .medium, design: .monospaced))
            Text(caption).font(.system(size: 11)).foregroundStyle(DesignTokens.Colors.ink2)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(Rectangle().strokeBorder(DesignTokens.Colors.ink, lineWidth: DesignTokens.hairline))
    }

    private func wpmCard(_ s: InsightsStats) -> some View {
        let wpm = s.wordsPerMinute ?? 0
        return VStack(alignment: .leading, spacing: 2) {
            Text("words per minute").font(.system(size: 11).monospaced()).foregroundStyle(DesignTokens.Colors.ink2)
            Text(wpm > 0 ? "\(Int(wpm.rounded()))" : "–").font(.system(size: 26, weight: .medium, design: .monospaced))
            Text(wpm > 0 ? String(format: "%.1f× faster than typing", wpm / InsightsTab.typingWPM) : "not yet")
                .font(.system(size: 11)).foregroundStyle(DesignTokens.Colors.ink2)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(DesignTokens.Colors.inkA08).frame(height: 6)
                    Rectangle().fill(DesignTokens.Colors.ink).frame(width: geo.size.width * min(1, wpm / InsightsTab.gaugeMax), height: 6)
                    Rectangle().fill(DesignTokens.Colors.ink2).frame(width: 1.5, height: 12)
                        .offset(x: geo.size.width * (InsightsTab.typingWPM / InsightsTab.gaugeMax), y: 0)
                }
            }
            .frame(height: 12).padding(.top, 8)
            HStack { Text("typing 40"); Spacer(); Text("you \(Int(wpm.rounded()))") }.font(.system(size: 10).monospaced()).foregroundStyle(DesignTokens.Colors.ink3)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(Rectangle().strokeBorder(DesignTokens.Colors.ink, lineWidth: DesignTokens.hairline))
    }

    private func categories(_ s: InsightsStats) -> some View {
        let total = max(1, s.categories.reduce(0) { $0 + $1.dictations })
        return VStack(alignment: .leading, spacing: 10) {
            if s.categories.isEmpty {
                Text("nothing yet").font(.system(size: 12)).foregroundStyle(DesignTokens.Colors.ink2)
            } else {
                GeometryReader { geo in
                    let shown = s.categories.filter { $0.dictations > 0 }
                    let usable = geo.size.width - 2 * CGFloat(max(0, shown.count - 1))
                    HStack(spacing: 2) {
                        ForEach(Array(s.categories.enumerated()), id: \.element.category) { i, c in
                            if c.dictations > 0 {
                                Rectangle().fill(InsightsTab.tone(i))
                                    .frame(width: usable * CGFloat(c.dictations) / CGFloat(total))
                            }
                        }
                    }
                    .frame(width: geo.size.width, alignment: .leading)
                    .clipped()
                }
                .frame(height: 10)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                    ForEach(Array(s.categories.enumerated()), id: \.element.category) { i, c in
                        HStack(spacing: 6) {
                            Rectangle().fill(InsightsTab.tone(i)).frame(width: 8, height: 8)
                            Text(c.category.displayName.lowercased()).font(.system(size: 12))
                            Spacer()
                            Text("\(Int((Double(c.dictations) / Double(total) * 100).rounded()))%").font(.system(size: 12).monospaced()).foregroundStyle(DesignTokens.Colors.ink2)
                        }
                    }
                }
            }
        }
        .padding(14)
    }

    private func topApps(_ s: InsightsStats) -> some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                if s.topApps.isEmpty { Text("nothing yet").font(.system(size: 12)).foregroundStyle(DesignTokens.Colors.ink2).padding(.vertical, 8) }
                ForEach(s.topApps, id: \.name) { a in
                    HStack {
                        Text(a.name.lowercased()).font(.system(size: 12)).lineLimit(1)
                        Spacer()
                        Text("\(a.words.formatted()) words").font(.system(size: 12).monospaced()).foregroundStyle(DesignTokens.Colors.ink2)
                    }
                    .padding(.vertical, 5)
                }
            }
            .padding(.horizontal, 14).padding(.top, 3).padding(.bottom, 8)
        }
        .scrollIndicators(.never)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func calendar(_ s: InsightsStats) -> some View {
        let byDate = Dictionary(uniqueKeysWithValues: s.activity.map { ($0.date, $0.dictations) })
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weeks = 16
        let start = cal.date(byAdding: .day, value: -(weeks * 7 - 1), to: today)!
        let maxCount = max(1, s.activity.map(\.dictations).max() ?? 1)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return HStack(alignment: .bottom, spacing: 12) {
            HStack(spacing: 3) {
                ForEach(0..<weeks, id: \.self) { w in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { d in
                            let date = cal.date(byAdding: .day, value: w * 7 + d, to: start)!
                            let n = byDate[f.string(from: date)] ?? 0
                            Rectangle()
                                .fill(DesignTokens.Colors.ink.opacity(n == 0 ? 0.08 : 0.3 + 0.7 * Double(n) / Double(maxCount)))
                                .frame(width: 11, height: 11)
                        }
                    }
                }
            }
            Spacer()
            HStack(spacing: 4) {
                Text("less").font(.system(size: 10).monospaced()).foregroundStyle(DesignTokens.Colors.ink3)
                ForEach([0.08, 0.3, 0.55, 0.8, 1.0], id: \.self) { o in Rectangle().fill(DesignTokens.Colors.ink.opacity(o)).frame(width: 9, height: 9) }
                Text("more").font(.system(size: 10).monospaced()).foregroundStyle(DesignTokens.Colors.ink3)
            }
        }
        .padding(14)
    }
}
