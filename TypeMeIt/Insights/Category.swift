// Assigns each dictation to a usage category from the app it was dictated
// into and, for browsers and terminals, from the focused window's title.
//
// Categories, and what lands in each:
//
// | Category           | Rule                                                                 |
// |--------------------|----------------------------------------------------------------------|
// | `aiPrompts`        | AI chat/agent apps (Claude, ChatGPT, Cursor, Windsurf, Perplexity…), a browser tab whose title names an AI assistant, or a terminal whose title names a coding agent (Claude Code, Codex, Aider…). |
// | `workMessages`     | Team chat: Slack, Microsoft Teams, Google Chat, Zoom, Mattermost.    |
// | `personalMessages` | Messages, WhatsApp, Telegram, Signal, Discord, Messenger, Viber, WeChat, LINE. |
// | `emails`           | Mail clients (Mail, Outlook, Superhuman, Spark, Mimestream, Thunderbird…) and webmail tabs (Gmail, Outlook, Proton, Fastmail…). |
// | `documents`        | Word processors and notes (Pages, Word, Notes, Notion, Obsidian, Craft, Bear, Google Docs/Sheets/Slides, Confluence…). |
// | `code`             | Editors and IDEs (VS Code, Xcode, JetBrains, Zed, Sublime), terminals without an agent in the title, GitHub/GitLab tabs. |
// | `other`            | Everything else, including browser tabs no rule recognises.          |
//
// Matching is case-insensitive. App rules match the app id (bundle id on
// macOS, executable name on Windows) by substring, or the app's display name
// exactly. Title rules match the window title by substring. Rules are tried
// in order, so put the more specific rule first where needles overlap
// (Notion Mail before Notion, Google Chat before Google Docs).

import Foundation

enum UsageCategory: String, Sendable, Codable, CaseIterable {
    case aiPrompts
    case workMessages
    case personalMessages
    case emails
    case documents
    case code
    case other

    var displayName: String {
        switch self {
        case .aiPrompts: "AI prompts"
        case .workMessages: "Work messages"
        case .personalMessages: "Personal messages"
        case .emails: "Emails"
        case .documents: "Documents"
        case .code: "Code"
        case .other: "Other"
        }
    }
}

enum Category {
    /// What an app is, before the window title is consulted.
    enum AppKind: Sendable, Equatable {
        /// The app alone decides the category.
        case fixed(UsageCategory)
        /// The category depends on the open tab; unknown titles are `other`.
        case browser
        /// The category depends on what runs inside; unknown titles are `code`.
        case terminal
    }

    enum AppMatch: Sendable {
        /// Substring of the lowercased app id.
        case id(String)
        /// The whole lowercased display name.
        case name(String)
    }

    static let appRules: [(AppMatch, AppKind)] = [
        // Browsers
        (.id("com.google.chrome"), .browser),
        (.id("chrome.exe"), .browser),
        (.id("com.apple.safari"), .browser),
        (.id("org.mozilla.firefox"), .browser),
        (.id("firefox.exe"), .browser),
        (.id("company.thebrowser.browser"), .browser),
        (.id("company.thebrowser.dia"), .browser),
        (.id("com.brave.browser"), .browser),
        (.id("brave.exe"), .browser),
        (.id("com.microsoft.edgemac"), .browser),
        (.id("msedge.exe"), .browser),
        (.id("com.vivaldi.vivaldi"), .browser),
        (.id("com.operasoftware.opera"), .browser),
        (.id("opera.exe"), .browser),
        (.id("com.kagi.kagimacos"), .browser),
        (.id("app.zen-browser.zen"), .browser),
        (.name("arc"), .browser),
        (.name("dia"), .browser),
        (.name("zen"), .browser),
        (.name("orion"), .browser),
        // Terminals
        (.id("com.apple.terminal"), .terminal),
        (.id("com.googlecode.iterm2"), .terminal),
        (.id("com.mitchellh.ghostty"), .terminal),
        (.id("dev.warp.warp"), .terminal),
        (.id("net.kovidgoyal.kitty"), .terminal),
        (.id("org.alacritty"), .terminal),
        (.id("io.alacritty"), .terminal),
        (.id("com.github.wez.wezterm"), .terminal),
        (.id("co.zeit.hyper"), .terminal),
        (.id("org.tabby"), .terminal),
        (.id("windowsterminal.exe"), .terminal),
        (.id("wt.exe"), .terminal),
        (.id("cmd.exe"), .terminal),
        (.id("powershell.exe"), .terminal),
        (.id("pwsh.exe"), .terminal),
        (.id("conhost.exe"), .terminal),
        (.id("alacritty.exe"), .terminal),
        (.id("wezterm-gui.exe"), .terminal),
        // AI chat and agent apps
        (.id("com.anthropic."), .fixed(.aiPrompts)),
        (.id("claude"), .fixed(.aiPrompts)),
        (.id("com.openai."), .fixed(.aiPrompts)),
        (.id("chatgpt"), .fixed(.aiPrompts)),
        (.id("com.todesktop.230313mzl4w4u92"), .fixed(.aiPrompts)), // Cursor
        (.name("cursor"), .fixed(.aiPrompts)),
        (.id("com.exafunction.windsurf"), .fixed(.aiPrompts)),
        (.name("windsurf"), .fixed(.aiPrompts)),
        (.id("perplexity"), .fixed(.aiPrompts)),
        (.id("com.google.gemini"), .fixed(.aiPrompts)),
        (.id("copilot"), .fixed(.aiPrompts)),
        (.id("com.electron.ollama"), .fixed(.aiPrompts)),
        (.id("ai.elementlabs.lmstudio"), .fixed(.aiPrompts)),
        (.id("xyz.chatboxapp"), .fixed(.aiPrompts)),
        (.id("com.mistral"), .fixed(.aiPrompts)),
        (.id("deepseek"), .fixed(.aiPrompts)),
        (.id("grok"), .fixed(.aiPrompts)),
        // Work messages
        (.id("com.tinyspeck.slackmacgap"), .fixed(.workMessages)),
        (.id("slack"), .fixed(.workMessages)),
        (.id("com.microsoft.teams"), .fixed(.workMessages)),
        (.id("ms-teams.exe"), .fixed(.workMessages)),
        (.id("teams.exe"), .fixed(.workMessages)),
        (.id("us.zoom.xos"), .fixed(.workMessages)),
        (.id("zoom.exe"), .fixed(.workMessages)),
        (.id("com.google.chat"), .fixed(.workMessages)),
        (.id("mattermost"), .fixed(.workMessages)),
        // Personal messages
        (.id("com.apple.mobilesms"), .fixed(.personalMessages)),
        (.name("messages"), .fixed(.personalMessages)),
        (.id("whatsapp"), .fixed(.personalMessages)),
        (.id("telegram"), .fixed(.personalMessages)),
        (.id("signal"), .fixed(.personalMessages)),
        (.id("com.hnc.discord"), .fixed(.personalMessages)),
        (.id("discord"), .fixed(.personalMessages)),
        (.id("com.facebook.archon"), .fixed(.personalMessages)),
        (.name("messenger"), .fixed(.personalMessages)),
        (.id("viber"), .fixed(.personalMessages)),
        (.id("com.tencent.xinwechat"), .fixed(.personalMessages)),
        (.name("wechat"), .fixed(.personalMessages)),
        (.id("jp.naver.line"), .fixed(.personalMessages)),
        (.id("com.beeper"), .fixed(.personalMessages)),
        // Email
        (.id("notion.mail"), .fixed(.emails)),
        (.id("com.apple.mail"), .fixed(.emails)),
        (.name("mail"), .fixed(.emails)),
        (.id("com.microsoft.outlook"), .fixed(.emails)),
        (.id("olk.exe"), .fixed(.emails)),
        (.id("outlook.exe"), .fixed(.emails)),
        (.id("superhuman"), .fixed(.emails)),
        (.id("com.readdle.smartemail"), .fixed(.emails)),
        (.name("spark"), .fixed(.emails)),
        (.id("mimestream"), .fixed(.emails)),
        (.id("airmail"), .fixed(.emails)),
        (.id("thunderbird"), .fixed(.emails)),
        (.id("mailmate"), .fixed(.emails)),
        (.id("canarymail"), .fixed(.emails)),
        (.id("postbox"), .fixed(.emails)),
        // Documents
        (.id("com.apple.iwork.pages"), .fixed(.documents)),
        (.id("com.apple.iwork.keynote"), .fixed(.documents)),
        (.id("com.apple.iwork.numbers"), .fixed(.documents)),
        (.id("com.microsoft.word"), .fixed(.documents)),
        (.id("winword.exe"), .fixed(.documents)),
        (.id("com.microsoft.powerpoint"), .fixed(.documents)),
        (.id("powerpnt.exe"), .fixed(.documents)),
        (.id("com.microsoft.excel"), .fixed(.documents)),
        (.id("excel.exe"), .fixed(.documents)),
        (.id("com.microsoft.onenote"), .fixed(.documents)),
        (.id("onenote.exe"), .fixed(.documents)),
        (.id("com.apple.notes"), .fixed(.documents)),
        (.name("notes"), .fixed(.documents)),
        (.id("com.apple.textedit"), .fixed(.documents)),
        (.id("notepad.exe"), .fixed(.documents)),
        (.id("notion.id"), .fixed(.documents)),
        (.name("notion"), .fixed(.documents)),
        (.id("md.obsidian"), .fixed(.documents)),
        (.id("obsidian"), .fixed(.documents)),
        (.id("com.lukilabs.lukiapp"), .fixed(.documents)), // Craft
        (.name("craft"), .fixed(.documents)),
        (.id("net.shinyfrog.bear"), .fixed(.documents)),
        (.name("bear"), .fixed(.documents)),
        (.id("pro.writer.mac"), .fixed(.documents)),
        (.name("ia writer"), .fixed(.documents)),
        (.id("com.ulyssesapp"), .fixed(.documents)),
        (.id("typora"), .fixed(.documents)),
        (.id("scrivener"), .fixed(.documents)),
        (.id("logseq"), .fixed(.documents)),
        (.id("evernote"), .fixed(.documents)),
        (.id("goodnotes"), .fixed(.documents)),
        (.id("com.agiletortoise.drafts"), .fixed(.documents)),
        // Code editors and IDEs
        (.id("com.microsoft.vscode"), .fixed(.code)),
        (.id("code.exe"), .fixed(.code)),
        (.id("vscodium"), .fixed(.code)),
        (.id("com.apple.dt.xcode"), .fixed(.code)),
        (.id("com.jetbrains"), .fixed(.code)),
        (.id("com.google.android.studio"), .fixed(.code)),
        (.id("com.sublimetext"), .fixed(.code)),
        (.id("dev.zed.zed"), .fixed(.code)),
        (.id("com.panic.nova"), .fixed(.code)),
        (.id("neovide"), .fixed(.code)),
        (.id("idea64.exe"), .fixed(.code)),
        (.id("pycharm64.exe"), .fixed(.code)),
        (.id("webstorm64.exe"), .fixed(.code)),
        (.id("goland64.exe"), .fixed(.code)),
        (.id("rider64.exe"), .fixed(.code)),
        (.id("clion64.exe"), .fixed(.code)),
        (.id("devenv.exe"), .fixed(.code)),
    ]

    /// Window-title rules for browsers. First match wins.
    static let browserTitleRules: [(String, UsageCategory)] = [
        // AI assistants
        ("claude", .aiPrompts),
        ("chatgpt", .aiPrompts),
        ("gemini", .aiPrompts),
        ("perplexity", .aiPrompts),
        ("copilot", .aiPrompts),
        ("grok", .aiPrompts),
        ("deepseek", .aiPrompts),
        ("mistral", .aiPrompts),
        ("notebooklm", .aiPrompts),
        ("character.ai", .aiPrompts),
        ("huggingchat", .aiPrompts),
        ("meta ai", .aiPrompts),
        ("lovable", .aiPrompts),
        ("bolt.new", .aiPrompts),
        ("v0.dev", .aiPrompts),
        // Work messages (before documents so Google Chat beats Google Docs)
        ("slack", .workMessages),
        ("microsoft teams", .workMessages),
        ("google chat", .workMessages),
        ("zoom", .workMessages),
        ("mattermost", .workMessages),
        // Personal messages
        ("whatsapp", .personalMessages),
        ("telegram", .personalMessages),
        ("messenger", .personalMessages),
        ("discord", .personalMessages),
        ("instagram", .personalMessages),
        // Email
        ("gmail", .emails),
        ("outlook", .emails),
        ("proton mail", .emails),
        ("fastmail", .emails),
        ("superhuman", .emails),
        ("yahoo mail", .emails),
        ("icloud mail", .emails),
        ("zoho mail", .emails),
        ("notion mail", .emails),
        ("hey.com", .emails),
        // Documents
        ("google docs", .documents),
        ("google sheets", .documents),
        ("google slides", .documents),
        ("google forms", .documents),
        ("notion", .documents),
        ("confluence", .documents),
        ("| coda", .documents),
        ("dropbox paper", .documents),
        ("onenote", .documents),
        ("microsoft word", .documents),
        ("quip", .documents),
        ("overleaf", .documents),
        ("hackmd", .documents),
        ("obsidian", .documents),
        ("substack", .documents),
        // Code
        ("github", .code),
        ("gitlab", .code),
        ("bitbucket", .code),
        ("stackblitz", .code),
        ("codesandbox", .code),
        ("codepen", .code),
        ("replit", .code),
        ("jupyter", .code),
        ("colab", .code),
    ]

    /// Window-title rules for terminals: coding agents that read typed prompts.
    static let terminalTitleRules: [(String, UsageCategory)] = [
        ("claude", .aiPrompts),
        ("codex", .aiPrompts),
        ("aider", .aiPrompts),
        ("gemini", .aiPrompts),
        ("copilot", .aiPrompts),
        ("opencode", .aiPrompts),
        ("goose", .aiPrompts),
    ]

    /// Category for one dictation. Returns `nil` when every input is missing
    /// or blank: such a row is unmeasured, not `other`, and the insights count
    /// it as unattributed instead of inventing a breakdown the data cannot
    /// support.
    static func classify(appId: String?, appName: String?, windowTitle: String?) -> UsageCategory? {
        let known = [appId, appName, windowTitle].contains { field in
            guard let field else { return false }
            return !field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard known else { return nil }

        let id = ScalarText(appId?.lowercased() ?? "")
        let name = ScalarText(appName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "")
        let title = ScalarText(windowTitle?.lowercased() ?? "")

        let kind = appRules.first { needle, _ in
            switch needle {
            case .id(let sub): !id.isEmpty && id.contains(sub)
            case .name(let exact): !name.isEmpty && name.equals(exact)
            }
        }?.1

        switch kind {
        case .fixed(let category): return category
        case .browser: return firstTitleMatch(title, browserTitleRules) ?? .other
        case .terminal: return firstTitleMatch(title, terminalTitleRules) ?? .code
        // Unknown apps still get a chance through their window title, which
        // covers web apps wrapped in unlisted browsers.
        case nil: return firstTitleMatch(title, browserTitleRules) ?? .other
        }
    }

    static func firstTitleMatch(_ title: ScalarText, _ rules: [(String, UsageCategory)]) -> UsageCategory? {
        if title.isEmpty { return nil }
        return rules.first { needle, _ in title.contains(needle) }?.1
    }
}

/// A string held as its Unicode scalars so that substring and equality checks
/// compare code points, the way Rust's `str` does. Swift's `String` operators
/// treat canonically equivalent spellings (precomposed vs. decomposed) as
/// equal, which would make the port classify and diff differently from the
/// original on such input.
struct ScalarText: Sendable {
    let scalars: [Unicode.Scalar]

    init(_ text: String) {
        scalars = Array(text.unicodeScalars)
    }

    var isEmpty: Bool { scalars.isEmpty }

    /// `needle` occurs as a contiguous run of scalars.
    func contains(_ needle: String) -> Bool {
        let sub = Array(needle.unicodeScalars)
        if sub.isEmpty { return true }
        guard scalars.count >= sub.count else { return false }
        for start in 0...(scalars.count - sub.count)
        where scalars[start..<(start + sub.count)].elementsEqual(sub) {
            return true
        }
        return false
    }

    /// Scalar-for-scalar equality with `other`.
    func equals(_ other: String) -> Bool {
        scalars.elementsEqual(other.unicodeScalars)
    }
}
