// Aggregates the transcription history into the numbers shown on the
// Insights page: words dictated, speaking rate, fixes, per-category usage
// and the daily streak.
//
// `Insights.compute` is pure over the rows it is handed, so the whole page can
// be checked with in-memory data. Month and day boundaries follow the
// `calendar` argument; the app passes `Calendar.current`.

import Foundation

/// The columns of one history entry the insights need.
struct InsightRow: Sendable {
    var timestamp: Date
    var transcript: String
    var postProcessed: String? = nil
    var postProcessRequested: Bool = false
    var durationMs: Int? = nil
    var dictionaryFixes: Int = 0
    var appId: String? = nil
    var appName: String? = nil
    var windowTitle: String? = nil
}

struct CategoryUsage: Sendable, Equatable {
    var category: UsageCategory
    var dictations: Int
    var words: Int
}

struct AppUsage: Sendable, Equatable {
    var name: String
    var dictations: Int
    var words: Int
}

struct DayActivity: Sendable, Equatable {
    /// Local calendar day as `YYYY-MM-DD`.
    var date: String
    var dictations: Int
    var words: Int
}

struct InsightsStats: Sendable, Equatable {
    var totalWords: Int
    var totalDictations: Int
    var wordsThisMonth: Int
    var wordsPreviousMonth: Int
    /// Spoken words per minute over the dictations that recorded a duration.
    var wordsPerMinute: Double?
    var timedDictations: Int
    /// Custom-word corrections applied by the fuzzy matcher.
    var dictionaryFixes: Int
    /// Words changed by post-processing where it ran.
    var postProcessFixes: Int
    var categories: [CategoryUsage]
    /// Dictations with no app recorded, which the categories exclude. Every
    /// entry saved before app attribution shipped counts here.
    var unattributed: Int
    var totalApps: Int
    var topApps: [AppUsage]
    var currentStreak: Int
    var longestStreak: Int
    var activeToday: Bool
    var activity: [DayActivity]
}

/// A calendar day in the caller's calendar: the key for month totals, the
/// activity map and streaks.
struct LocalDay: Hashable, Comparable, Sendable {
    var year: Int
    var month: Int
    var day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        year = components.year ?? 0
        month = components.month ?? 0
        day = components.day ?? 0
    }

    static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// `YYYY-MM-DD`.
    var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// The day `count` days away, or `nil` when the calendar cannot place it.
    /// Anchored at noon so a missing or doubled midnight (DST) cannot move the
    /// result onto a neighbouring day.
    func adding(days count: Int, calendar: Calendar) -> LocalDay? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        guard let noon = calendar.date(from: components),
              let shifted = calendar.date(byAdding: .day, value: count, to: noon)
        else { return nil }
        return LocalDay(shifted, calendar: calendar)
    }
}

enum Insights {
    static let topApps = 8

    /// Whitespace-separated tokens, as Rust's `str::split_whitespace`: split
    /// on Unicode `White_Space` scalars, empty pieces dropped.
    static func wordCount(_ text: String) -> Int {
        var count = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace {
                inWord = false
            } else if !inWord {
                inWord = true
                count += 1
            }
        }
        return count
    }

    /// Number of custom-word corrections between the raw transcript and the
    /// corrected one: each run of changed tokens is one fix.
    static func countDictionaryFixes(raw: String, corrected: String) -> Int {
        if raw.unicodeScalars.elementsEqual(corrected.unicodeScalars) {
            return 0
        }
        switch TokenDiff.hunks(raw, corrected) {
        case .some(let hunks): return hunks.count
        // Too long to diff token by token; the texts differ, so count one.
        case .none: return 1
        }
    }

    /// Words a post-processing pass changed: the longer side of every hunk.
    static func countPostProcessFixes(raw: String, processed: String) -> Int {
        if raw.unicodeScalars.elementsEqual(processed.unicodeScalars) {
            return 0
        }
        switch TokenDiff.hunks(raw, processed) {
        case .some(let hunks):
            return hunks.reduce(0) { $0 + max($1.removed.count, $1.inserted.count) }
        case .none:
            return max(abs(wordCount(raw) - wordCount(processed)), 1)
        }
    }

    private static func previousMonth(of today: LocalDay) -> (year: Int, month: Int) {
        today.month == 1 ? (today.year - 1, 12) : (today.year, today.month - 1)
    }

    static func compute(_ rows: [InsightRow], now: Date = Date(), calendar: Calendar = .current) -> InsightsStats {
        let today = LocalDay(now, calendar: calendar)

        var totalWords = 0
        var wordsThisMonth = 0
        var wordsPreviousMonth = 0
        var timedWords = 0
        var timedMs = 0
        var timedDictations = 0
        var dictionaryFixes = 0
        var postProcessFixes = 0
        var unattributed = 0
        var byCategory: [UsageCategory: (dictations: Int, words: Int)] = [:]
        var byApp: [String: (name: String, dictations: Int, words: Int)] = [:]
        var byDay: [LocalDay: (dictations: Int, words: Int)] = [:]

        let thisMonth = (today.year, today.month)
        let prevMonth = previousMonth(of: today)

        for row in rows {
            let words = wordCount(row.transcript)
            totalWords += words

            let day = LocalDay(row.timestamp, calendar: calendar)
            let month = (day.year, day.month)
            if month == thisMonth {
                wordsThisMonth += words
            } else if month == (prevMonth.year, prevMonth.month) {
                wordsPreviousMonth += words
            }
            byDay[day, default: (0, 0)].dictations += 1
            byDay[day, default: (0, 0)].words += words

            if let ms = row.durationMs, ms > 0 {
                timedWords += words
                timedMs += ms
                timedDictations += 1
            }

            dictionaryFixes += max(row.dictionaryFixes, 0)
            if row.postProcessRequested, let processed = row.postProcessed {
                postProcessFixes += countPostProcessFixes(raw: row.transcript, processed: processed)
            }

            // A row with nothing known about its destination is not "Other", it
            // is unmeasured. Counting it as a category would report a breakdown
            // the data cannot support.
            if let category = Category.classify(
                appId: row.appId, appName: row.appName, windowTitle: row.windowTitle
            ) {
                byCategory[category, default: (0, 0)].dictations += 1
                byCategory[category, default: (0, 0)].words += words
            } else {
                unattributed += 1
            }

            let trimmedName = row.appName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = (trimmedName?.isEmpty == false ? trimmedName : nil) ?? row.appId
            if let name = displayName {
                let key: String
                if let id = row.appId, !id.isEmpty {
                    key = id.lowercased()
                } else {
                    key = name.lowercased()
                }
                var entry = byApp[key] ?? (name: name, dictations: 0, words: 0)
                entry.dictations += 1
                entry.words += words
                byApp[key] = entry
            }
        }

        var wordsPerMinute: Double? = nil
        if timedMs > 0 {
            let wpm = Double(timedWords) / (Double(timedMs) / 60_000.0)
            if wpm.isFinite {
                wordsPerMinute = wpm
            }
        }

        let categories = UsageCategory.allCases.map { category in
            let (dictations, words) = byCategory[category] ?? (0, 0)
            return CategoryUsage(category: category, dictations: dictations, words: words)
        }

        let totalApps = byApp.count
        var topApps = byApp.values.map { AppUsage(name: $0.name, dictations: $0.dictations, words: $0.words) }
        // Most used first, by the words the list shows; then by dictations, then name.
        topApps.sort { a, b in
            if a.words != b.words { return a.words > b.words }
            if a.dictations != b.dictations { return a.dictations > b.dictations }
            return a.name.unicodeScalars.lexicographicallyPrecedes(b.name.unicodeScalars)
        }
        if topApps.count > Self.topApps {
            topApps.removeSubrange(Self.topApps...)
        }

        let (currentStreak, longestStreak) = streaks(byDay, today: today, calendar: calendar)
        let activeToday = byDay[today] != nil

        let activity = byDay.keys.sorted().map { day in
            let (dictations, words) = byDay[day] ?? (0, 0)
            return DayActivity(date: day.isoString, dictations: dictations, words: words)
        }

        return InsightsStats(
            totalWords: totalWords,
            totalDictations: rows.count,
            wordsThisMonth: wordsThisMonth,
            wordsPreviousMonth: wordsPreviousMonth,
            wordsPerMinute: wordsPerMinute,
            timedDictations: timedDictations,
            dictionaryFixes: dictionaryFixes,
            postProcessFixes: postProcessFixes,
            categories: categories,
            unattributed: unattributed,
            totalApps: totalApps,
            topApps: topApps,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            activeToday: activeToday,
            activity: activity
        )
    }

    /// `(current, longest)` runs of consecutive active days. The current streak
    /// is still alive on a day with no dictation yet, so it is counted back from
    /// yesterday when today is empty.
    static func streaks(
        _ byDay: [LocalDay: (dictations: Int, words: Int)],
        today: LocalDay,
        calendar: Calendar
    ) -> (current: Int, longest: Int) {
        var longest = 0
        var run = 0
        var previous: LocalDay? = nil
        for day in byDay.keys.sorted() {
            if let next = previous?.adding(days: 1, calendar: calendar), next == day {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = day
        }

        var cursor: LocalDay?
        if byDay[today] != nil {
            cursor = today
        } else if let yesterday = today.adding(days: -1, calendar: calendar), byDay[yesterday] != nil {
            cursor = yesterday
        } else {
            cursor = nil
        }
        var current = 0
        while let day = cursor {
            if byDay[day] == nil {
                break
            }
            current += 1
            cursor = day.adding(days: -1, calendar: calendar)
        }
        return (current, longest)
    }
}

// MARK: - Token diff

/// Token-level alignment of a transcript against an edited version, the port
/// of `learning::diff`. It lives here until the Learning module is ported;
/// move it there and drop this copy at that point.
///
/// Tokens are compared on their match key (alphanumeric, lowercased) so that
/// punctuation and capitalisation differences do not register as changes on
/// their own. Runs of changed tokens become hunks; a hunk with both a removed
/// and an inserted side is a replacement.
enum TokenDiff {
    /// Longest input, in tokens, that is diffed at all. Beyond this an edit is
    /// treated as a rewrite rather than a correction.
    static let maxTokens = 400

    struct Hunk: Equatable, Sendable {
        /// Tokens removed from the original, in order. Empty for a pure insertion.
        var removed: [String]
        /// Tokens inserted by the edit, in order. Empty for a pure deletion.
        var inserted: [String]

        var isReplacement: Bool {
            !removed.isEmpty && !inserted.isEmpty
        }
    }

    /// Lowercased alphanumeric characters of `token`, the same key the custom
    /// words matcher uses. Alphanumeric is Rust's `char::is_alphanumeric`:
    /// the `Alphabetic` property or a `N*` general category.
    static func matchKey(_ token: String) -> String {
        var key = ""
        for scalar in token.unicodeScalars where isAlphanumeric(scalar) {
            key += scalar.properties.lowercaseMapping
        }
        return key
    }

    private static func isAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.properties.isAlphabetic {
            return true
        }
        switch scalar.properties.generalCategory {
        case .decimalNumber, .letterNumber, .otherNumber: return true
        default: return false
        }
    }

    /// Rust's `str::split_whitespace`: split on Unicode `White_Space` scalars,
    /// empty pieces dropped.
    static func tokens(_ text: String) -> [String] {
        var out: [String] = []
        var current = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace {
                if !current.isEmpty {
                    out.append(String(current))
                    current = String.UnicodeScalarView()
                }
            } else {
                current.append(scalar)
            }
        }
        if !current.isEmpty {
            out.append(String(current))
        }
        return out
    }

    /// All hunks between `original` and `edited`, or `nil` when either side is
    /// too long to diff.
    static func hunks(_ original: String, _ edited: String) -> [Hunk]? {
        let a = tokens(original)
        let b = tokens(edited)
        if a.count > maxTokens || b.count > maxTokens {
            return nil
        }
        // Keys as scalar arrays so equality is code-point equality, not
        // canonical equivalence.
        let ka = a.map { Array(matchKey($0).unicodeScalars) }
        let kb = b.map { Array(matchKey($0).unicodeScalars) }

        // Classic LCS table over match keys, flattened row-major with
        // `(m + 1)` columns.
        let n = ka.count
        let m = kb.count
        let width = m + 1
        var lcs = [Int](repeating: 0, count: (n + 1) * width)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i * width + j] = ka[i] == kb[j]
                    ? lcs[(i + 1) * width + (j + 1)] + 1
                    : max(lcs[(i + 1) * width + j], lcs[i * width + (j + 1)])
            }
        }

        var out: [Hunk] = []
        var current: Hunk? = nil
        var i = 0
        var j = 0
        while i < n || j < m {
            let matched = i < n && j < m && ka[i] == kb[j]
            if matched {
                if let hunk = current {
                    out.append(hunk)
                    current = nil
                }
                i += 1
                j += 1
                continue
            }
            var hunk = current ?? Hunk(removed: [], inserted: [])
            let takeFromA = j >= m || (i < n && lcs[(i + 1) * width + j] >= lcs[i * width + (j + 1)])
            if takeFromA {
                hunk.removed.append(a[i])
                i += 1
            } else {
                hunk.inserted.append(b[j])
                j += 1
            }
            current = hunk
        }
        if let hunk = current {
            out.append(hunk)
        }
        return out
    }
}
