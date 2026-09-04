import AppKit
import Foundation
import Observation

/// Checks the GitHub releases feed. Opens the release page; never installs.
@MainActor
@Observable
final class Updates {
    static let shared = Updates()

    struct Available: Equatable, Sendable {
        var version: String
        var url: URL
    }

    private(set) var available: Available?
    private(set) var checking = false

    private init() {}

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    func checkIfDue() {
        let settings = Settings.shared
        guard settings.checkForUpdates else { return }
        if let last = settings.lastUpdateCheck, Date().timeIntervalSince(last) < 24 * 3600 { return }
        Task { _ = await check() }
    }

    /// Returns the newer version if there is one, nil when up to date or on error (logged).
    func check() async -> Available? {
        checking = true
        defer { checking = false }
        Settings.shared.lastUpdateCheck = Date()
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Fixed.updatesOwner)/\(Fixed.updatesRepo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                Log.updates.notice("Release feed returned \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                available = nil
                return nil
            }
            struct Release: Decodable { var tag_name: String; var html_url: String }
            let release = try JSONDecoder().decode(Release.self, from: data)
            var tag = release.tag_name
            if tag.hasPrefix("v") { tag.removeFirst() }
            if tag.compare(Updates.currentVersion, options: .numeric) == .orderedDescending, let url = URL(string: release.html_url) {
                available = Available(version: tag, url: url)
            } else {
                available = nil
            }
            return available
        } catch {
            Log.updates.error("Update check failed: \(error.localizedDescription)")
            return nil
        }
    }

    func open() {
        if let url = available?.url { NSWorkspace.shared.open(url) }
    }
}
