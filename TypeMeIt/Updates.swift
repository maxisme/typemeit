import AppKit
import Foundation
import Observation
import Sparkle

/// Sparkle's updater, wrapped so the rest of the app never imports Sparkle.
///
/// The feed is the appcast attached to the latest GitHub release, signed with the
/// EdDSA key whose public half is `SUPublicEDKey` in the Info.plist. Sparkle
/// downloads the same notarized DMG the website hands out, so an update installs
/// the artifact that was actually tested.
@MainActor
@Observable
final class Updates: NSObject {
    static let shared = Updates()

    /// `startingUpdater: true` schedules the background check itself, on Sparkle's
    /// own timer and defaults key. That replaces the hand-rolled 24-hour check.
    private let controller = SPUStandardUpdaterController(startingUpdater: !Updates.isDevBuild, updaterDelegate: nil, userDriverDelegate: nil)

    /// The dev build is not in the appcast, and an update would replace it
    /// with the release, so it never checks.
    static let isDevBuild = Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true

    @ObservationIgnored private var observation: NSKeyValueObservation?

    /// Mirrors `SPUUpdater.canCheckForUpdates` so the menu item can disable itself
    /// while a check is already in flight.
    private(set) var canCheck = !Updates.isDevBuild

    private override init() {
        super.init()
        guard !Updates.isDevBuild else { return }
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            Task { @MainActor in self?.canCheck = updater.canCheckForUpdates }
        }
    }

    /// The automatic-check preference. Sparkle owns the storage; reading it back
    /// from the updater keeps the Settings toggle and Sparkle from disagreeing.
    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Shows Sparkle's own UI, including the "you're up to date" case.
    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}
