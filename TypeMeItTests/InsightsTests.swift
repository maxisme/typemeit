import Foundation
import XCTest
@testable import TypeMeIt

/// Gregorian calendar in UTC, so every date in these tests is a fixed
/// instant regardless of the machine's zone.
private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

/// 10:00 UTC on the given day.
private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    utc.date(from: DateComponents(year: year, month: month, day: day, hour: 10))!
}

private func row(_ date: Date, _ text: String) -> InsightRow {
    InsightRow(timestamp: date, transcript: text)
}

private func compute(_ rows: [InsightRow], today: Date) -> InsightsStats {
    Insights.compute(rows, now: today, calendar: utc)
}

// MARK: - Category

final class CategoryTests: XCTestCase {
    private func classify(_ appId: String?, _ appName: String?, _ windowTitle: String?) -> UsageCategory? {
        Category.classify(appId: appId, appName: appName, windowTitle: windowTitle)
    }

    func testNothingKnownIsUnattributed() {
        XCTAssertNil(classify(nil, nil, nil))
        XCTAssertNil(classify("", "", ""))
        XCTAssertNil(classify("  ", " \n", "\t"))
    }

    func testNativeAppsClassifyByBundleId() {
        XCTAssertEqual(classify("com.tinyspeck.slackmacgap", "Slack", nil), .workMessages)
        XCTAssertEqual(classify("com.apple.MobileSMS", "Messages", "Alice"), .personalMessages)
        XCTAssertEqual(classify("com.apple.mail", "Mail", "Inbox"), .emails)
        XCTAssertEqual(classify("notion.id", "Notion", "Roadmap"), .documents)
        XCTAssertEqual(classify("com.microsoft.VSCode", "Code", "main.rs"), .code)
        XCTAssertEqual(classify("com.anthropic.claudefordesktop", "Claude", "Claude"), .aiPrompts)
    }

    func testWindowsAppsClassifyByExecutableName() {
        XCTAssertEqual(classify("slack.exe", "Slack", nil), .workMessages)
        XCTAssertEqual(classify("olk.exe", "olk", nil), .emails)
        XCTAssertEqual(classify("winword.exe", "WINWORD", nil), .documents)
        XCTAssertEqual(classify("chrome.exe", "chrome", "Inbox - Gmail - Google Chrome"), .emails)
    }

    func testDisplayNameMatchesAreExact() {
        XCTAssertEqual(classify(nil, "Mail", nil), .emails)
        XCTAssertEqual(classify(nil, "Mailtrack Helper", nil), .other)
        XCTAssertEqual(classify(nil, "Arc", "Claude"), .aiPrompts)
    }

    func testBrowsersClassifyByTabTitle() {
        let chrome = "com.google.Chrome"
        XCTAssertEqual(classify(chrome, "Google Chrome", "Claude - Google Chrome"), .aiPrompts)
        XCTAssertEqual(classify(chrome, "Google Chrome", "ChatGPT"), .aiPrompts)
        XCTAssertEqual(classify(chrome, "Google Chrome", "Inbox (3) - max@example.com - Gmail"), .emails)
        XCTAssertEqual(classify(chrome, "Google Chrome", "Q3 plan - Google Docs"), .documents)
        XCTAssertEqual(classify(chrome, "Google Chrome", "general - Acme - Slack"), .workMessages)
        XCTAssertEqual(classify(chrome, "Google Chrome", "WhatsApp"), .personalMessages)
        XCTAssertEqual(classify(chrome, "Google Chrome", "Pull Request #12 · acme/app - GitHub"), .code)
        XCTAssertEqual(classify(chrome, "Google Chrome", "BBC News"), .other)
        XCTAssertEqual(classify(chrome, "Google Chrome", nil), .other)
    }

    func testGoogleChatBeatsGoogleDocsInTitleRules() {
        XCTAssertEqual(classify("com.apple.Safari", "Safari", "Google Chat"), .workMessages)
    }

    func testTerminalsAreCodeUnlessAnAgentIsInTheTitle() {
        let ghostty = "com.mitchellh.ghostty"
        XCTAssertEqual(classify(ghostty, "Ghostty", "zsh"), .code)
        XCTAssertEqual(classify(ghostty, "Ghostty", nil), .code)
        XCTAssertEqual(classify(ghostty, "Ghostty", "✳ Claude Code — handy"), .aiPrompts)
        XCTAssertEqual(classify("com.apple.Terminal", "Terminal", "codex — 80×24"), .aiPrompts)
    }

    func testUnknownAppsFallBackToTitleRules() {
        XCTAssertEqual(classify("com.example.kiosk", "Kiosk", "Gmail"), .emails)
        XCTAssertEqual(classify("com.example.kiosk", "Kiosk", "Settings"), .other)
    }

    func testEveryCategoryIsListedOnce() {
        var seen = Set<UsageCategory>()
        for category in UsageCategory.allCases {
            XCTAssertTrue(seen.insert(category).inserted, "\(category) listed twice")
        }
        XCTAssertEqual(seen.count, 7)
    }

    func testDisplayNames() {
        XCTAssertEqual(UsageCategory.allCases.map(\.displayName), [
            "AI prompts", "Work messages", "Personal messages", "Emails", "Documents", "Code", "Other",
        ])
    }

    func testRawValuesAreCamelCase() {
        XCTAssertEqual(UsageCategory.allCases.map(\.rawValue), [
            "aiPrompts", "workMessages", "personalMessages", "emails", "documents", "code", "other",
        ])
    }
}

// MARK: - Insights

final class InsightsTests: XCTestCase {
    func testEmptyHistoryIsAllZeroes() {
        let stats = compute([], today: day(2026, 9, 3))
        XCTAssertEqual(stats.totalWords, 0)
        XCTAssertEqual(stats.totalDictations, 0)
        XCTAssertNil(stats.wordsPerMinute)
        XCTAssertEqual(stats.currentStreak, 0)
        XCTAssertEqual(stats.longestStreak, 0)
        XCTAssertFalse(stats.activeToday)
        XCTAssertTrue(stats.activity.isEmpty)
        XCTAssertEqual(stats.totalApps, 0)
        XCTAssertEqual(stats.categories.count, UsageCategory.allCases.count)
        XCTAssertTrue(stats.categories.allSatisfy { $0.dictations == 0 })
        XCTAssertEqual(stats.unattributed, 0)
    }

    func testWordsAndMonthsAreTotalledPerLocalDay() {
        let today = day(2026, 9, 3)
        let rows = [
            row(day(2026, 9, 1), "one two three"),
            row(day(2026, 9, 3), "four five"),
            row(day(2026, 8, 30), "six"),
            row(day(2026, 7, 4), "seven eight"),
        ]
        let stats = compute(rows, today: today)
        XCTAssertEqual(stats.totalWords, 8)
        XCTAssertEqual(stats.totalDictations, 4)
        XCTAssertEqual(stats.wordsThisMonth, 5)
        XCTAssertEqual(stats.wordsPreviousMonth, 1)
        XCTAssertTrue(stats.activeToday)
        XCTAssertEqual(stats.activity, [
            DayActivity(date: "2026-07-04", dictations: 1, words: 2),
            DayActivity(date: "2026-08-30", dictations: 1, words: 1),
            DayActivity(date: "2026-09-01", dictations: 1, words: 3),
            DayActivity(date: "2026-09-03", dictations: 1, words: 2),
        ])
    }

    func testDayBoundariesFollowTheCalendarTimeZone() {
        // 23:30 UTC on 2 September is already 3 September in Tokyo.
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let lateEvening = utc.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 23, minute: 30))!
        let rows = [row(lateEvening, "one two")]

        let inUtc = Insights.compute(rows, now: day(2026, 9, 3), calendar: utc)
        XCTAssertEqual(inUtc.activity, [DayActivity(date: "2026-09-02", dictations: 1, words: 2)])
        XCTAssertFalse(inUtc.activeToday)

        let inTokyo = Insights.compute(rows, now: day(2026, 9, 3), calendar: tokyo)
        XCTAssertEqual(inTokyo.activity, [DayActivity(date: "2026-09-03", dictations: 1, words: 2)])
        XCTAssertTrue(inTokyo.activeToday)
    }

    func testPreviousMonthWrapsTheYear() {
        let rows = [row(day(2025, 12, 31), "a b c"), row(day(2026, 1, 2), "d")]
        let stats = compute(rows, today: day(2026, 1, 15))
        XCTAssertEqual(stats.wordsThisMonth, 1)
        XCTAssertEqual(stats.wordsPreviousMonth, 3)
    }

    func testWordsPerMinuteUsesOnlyTimedDictations() {
        var timed = row(day(2026, 9, 3), "one two three four five six seven eight nine ten")
        timed.durationMs = 4_000
        var zero = row(day(2026, 9, 3), "ignored words here")
        zero.durationMs = 0
        let untimed = row(day(2026, 9, 3), "also ignored")
        let stats = compute([timed, zero, untimed], today: day(2026, 9, 3))
        XCTAssertEqual(stats.timedDictations, 1)
        XCTAssertEqual(stats.wordsPerMinute, 150.0)
    }

    func testFixesComeFromTheDictionaryCounterAndPostProcessingDiffs() {
        var a = row(day(2026, 9, 3), "we shipped handy today")
        a.dictionaryFixes = 2
        a.postProcessRequested = true
        a.postProcessed = "We shipped handy today."
        var b = row(day(2026, 9, 3), "meet at five pm tomorrow ok")
        b.postProcessRequested = true
        b.postProcessed = "Meet at 5pm tomorrow."
        var c = row(day(2026, 9, 3), "not requested but present")
        c.postProcessed = "completely different text"
        let stats = compute([a, b, c], today: day(2026, 9, 3))
        XCTAssertEqual(stats.dictionaryFixes, 2)
        // a: punctuation and case only; b: "five pm" -> "5pm" (2) and "ok" dropped (1).
        XCTAssertEqual(stats.postProcessFixes, 3)
    }

    func testDictionaryFixCounterCountsRunsOfChangedTokens() {
        XCTAssertEqual(Insights.countDictionaryFixes(raw: "same text", corrected: "same text"), 0)
        XCTAssertEqual(
            Insights.countDictionaryFixes(
                raw: "charge b is great and open a i",
                corrected: "ChargeBee is great and OpenAI"
            ),
            2
        )
    }

    func testFixCountersFallBackWhenTooLongToDiff() {
        let long = Array(repeating: "word", count: TokenDiff.maxTokens + 1).joined(separator: " ")
        XCTAssertEqual(Insights.countDictionaryFixes(raw: long, corrected: "word"), 1)
        XCTAssertEqual(Insights.countPostProcessFixes(raw: long, processed: "word"), TokenDiff.maxTokens)
        XCTAssertEqual(Insights.countPostProcessFixes(raw: long, processed: long + "."), 1)
    }

    func testWordCountSplitsOnUnicodeWhitespace() {
        XCTAssertEqual(Insights.wordCount(""), 0)
        XCTAssertEqual(Insights.wordCount("   "), 0)
        XCTAssertEqual(Insights.wordCount("  one   two\tthree\nfour  "), 4)
        XCTAssertEqual(Insights.wordCount("a\u{00A0}b\u{3000}c"), 3)
        XCTAssertEqual(Insights.wordCount("no\u{200B}break"), 1)
    }

    func testCategoriesAndAppsAreTallied() {
        var slack = row(day(2026, 9, 3), "hello team")
        slack.appId = "com.tinyspeck.slackmacgap"
        slack.appName = "Slack"
        var slackAgain = slack
        slackAgain.transcript = "one more"
        var chrome = row(day(2026, 9, 3), "draft an email please")
        chrome.appId = "com.google.Chrome"
        chrome.appName = "Google Chrome"
        chrome.windowTitle = "Inbox - Gmail"
        let unknown = row(day(2026, 9, 3), "x")

        let stats = compute([slack, slackAgain, chrome, unknown], today: day(2026, 9, 3))

        func usage(_ category: UsageCategory) -> CategoryUsage? {
            stats.categories.first { $0.category == category }
        }
        XCTAssertEqual(usage(.workMessages), CategoryUsage(category: .workMessages, dictations: 2, words: 4))
        XCTAssertEqual(usage(.emails), CategoryUsage(category: .emails, dictations: 1, words: 4))
        // The row with no app at all is unmeasured, not "Other".
        XCTAssertEqual(usage(.other), CategoryUsage(category: .other, dictations: 0, words: 0))
        XCTAssertEqual(stats.unattributed, 1)
        XCTAssertEqual(usage(.aiPrompts), CategoryUsage(category: .aiPrompts, dictations: 0, words: 0))

        XCTAssertEqual(stats.totalApps, 2)
        XCTAssertEqual(stats.topApps, [
            AppUsage(name: "Slack", dictations: 2, words: 4),
            AppUsage(name: "Google Chrome", dictations: 1, words: 4),
        ])
    }

    func testTopAppsBreakTiesByNameAndCapAtEight() {
        let names = ["Zed", "Arc", "Mail", "Slack", "Notes", "Bear", "Craft", "Dia", "Orion", "Kitty"]
        var rows: [InsightRow] = []
        for name in names {
            var entry = row(day(2026, 9, 3), "a")
            entry.appId = "app.\(name.lowercased())"
            entry.appName = name
            rows.append(entry)
        }
        var busy = row(day(2026, 9, 3), "b c")
        busy.appId = "app.orion"
        busy.appName = "Orion"
        rows.append(busy)

        let stats = compute(rows, today: day(2026, 9, 3))
        XCTAssertEqual(stats.totalApps, 10)
        XCTAssertEqual(stats.topApps.count, Insights.topApps)
        XCTAssertEqual(stats.topApps.map(\.name), ["Orion", "Arc", "Bear", "Craft", "Dia", "Kitty", "Mail", "Notes"])
        XCTAssertEqual(stats.topApps.first, AppUsage(name: "Orion", dictations: 2, words: 3))
    }

    func testAppsAreKeyedByLowercasedIdAndFallBackToName() {
        var upper = row(day(2026, 9, 3), "a")
        upper.appId = "com.google.Chrome"
        upper.appName = "Google Chrome"
        var lower = row(day(2026, 9, 3), "b c")
        lower.appId = "com.google.chrome"
        lower.appName = "Chrome"
        var nameOnly = row(day(2026, 9, 3), "d")
        nameOnly.appName = "  Kiosk  "
        var idOnly = row(day(2026, 9, 3), "e")
        idOnly.appId = "com.example.kiosk"

        let stats = compute([upper, lower, nameOnly, idOnly], today: day(2026, 9, 3))
        XCTAssertEqual(stats.totalApps, 3)
        XCTAssertEqual(stats.topApps, [
            AppUsage(name: "Google Chrome", dictations: 2, words: 3),
            AppUsage(name: "Kiosk", dictations: 1, words: 1),
            AppUsage(name: "com.example.kiosk", dictations: 1, words: 1),
        ])
    }

    func testRowsWithoutAnAppAreUnattributedButStillCountAsWords() {
        var blankName = row(day(2026, 9, 3), "four five")
        blankName.appName = "   "
        let rows = [row(day(2026, 9, 3), "one two three"), blankName]
        let stats = compute(rows, today: day(2026, 9, 3))
        XCTAssertEqual(stats.unattributed, 2)
        XCTAssertEqual(stats.totalWords, 5)
        XCTAssertEqual(stats.totalDictations, 2)
        XCTAssertTrue(stats.categories.allSatisfy { $0.dictations == 0 })
        XCTAssertEqual(stats.totalApps, 0)
    }

    func testStreaksCountConsecutiveDays() {
        let today = day(2026, 9, 3)
        let rows = [
            row(day(2026, 8, 10), "a"),
            row(day(2026, 8, 11), "a"),
            row(day(2026, 8, 12), "a"),
            row(day(2026, 8, 13), "a"),
            row(day(2026, 9, 2), "a"),
            row(day(2026, 9, 3), "a"),
        ]
        let stats = compute(rows, today: today)
        XCTAssertEqual(stats.currentStreak, 2)
        XCTAssertEqual(stats.longestStreak, 4)
    }

    func testStreakSurvivesAnEmptyTodayButNotAnEmptyYesterday() {
        let today = day(2026, 9, 3)
        let alive = [row(day(2026, 9, 1), "a"), row(day(2026, 9, 2), "a")]
        let aliveStats = compute(alive, today: today)
        XCTAssertEqual(aliveStats.currentStreak, 2)
        XCTAssertFalse(aliveStats.activeToday)

        let broken = [row(day(2026, 8, 31), "a"), row(day(2026, 9, 1), "a")]
        let brokenStats = compute(broken, today: today)
        XCTAssertEqual(brokenStats.currentStreak, 0)
        XCTAssertEqual(brokenStats.longestStreak, 2)
    }

    func testStreaksCrossMonthAndYearBoundaries() {
        let rows = [
            row(day(2025, 12, 30), "a"),
            row(day(2025, 12, 31), "a"),
            row(day(2026, 1, 1), "a"),
            row(day(2026, 1, 2), "a"),
        ]
        let stats = compute(rows, today: day(2026, 1, 2))
        XCTAssertEqual(stats.currentStreak, 4)
        XCTAssertEqual(stats.longestStreak, 4)
    }
}

// MARK: - Token diff

final class TokenDiffTests: XCTestCase {
    private func replacements(_ original: String, _ edited: String) -> [(String, String)] {
        TokenDiff.hunks(original, edited)!
            .filter(\.isReplacement)
            .map { ($0.removed.joined(separator: " "), $0.inserted.joined(separator: " ")) }
    }

    func testIdenticalTextHasNoHunks() {
        XCTAssertEqual(TokenDiff.hunks("we moved billing", "we moved billing"), [])
    }

    func testSingleWordReplacement() {
        let found = replacements("moved billing to Charge B last week", "moved billing to ChargeBee last week")
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].0, "Charge B")
        XCTAssertEqual(found[0].1, "ChargeBee")
    }

    func testPunctuationAndCaseAloneAreNotChanges() {
        XCTAssertEqual(TokenDiff.hunks("hello world", "Hello, world."), [])
    }

    func testInsertionAndDeletionAreNotReplacements() {
        let inserted = TokenDiff.hunks("send the report", "send the full report")!
        XCTAssertEqual(inserted.count, 1)
        XCTAssertFalse(inserted[0].isReplacement)
        let deleted = TokenDiff.hunks("send the full report", "send the report")!
        XCTAssertEqual(deleted.count, 1)
        XCTAssertFalse(deleted[0].isReplacement)
    }

    func testMultipleReplacementsStaySeparate() {
        let found = replacements(
            "Ask pree yanka to move the zen tricks data",
            "Ask Priyanka to move the Zentrix data"
        )
        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(found[0].0, "pree yanka")
        XCTAssertEqual(found[0].1, "Priyanka")
        XCTAssertEqual(found[1].0, "zen tricks")
        XCTAssertEqual(found[1].1, "Zentrix")
    }

    func testTooLongIsNil() {
        let long = Array(repeating: "word", count: TokenDiff.maxTokens + 1).joined(separator: " ")
        XCTAssertNil(TokenDiff.hunks(long, "word"))
    }

    func testMatchKeyKeepsOnlyLowercasedAlphanumerics() {
        XCTAssertEqual(TokenDiff.matchKey("Hello,"), "hello")
        XCTAssertEqual(TokenDiff.matchKey("(5pm)"), "5pm")
        XCTAssertEqual(TokenDiff.matchKey("Ünïcödé!"), "ünïcödé")
        XCTAssertEqual(TokenDiff.matchKey("---"), "")
    }
}
