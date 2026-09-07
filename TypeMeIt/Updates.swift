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
///
/// Sparkle never shows its own windows here. It checks on launch and then on its
/// hourly timer, downloads whatever it finds, and reports where it got to through
/// `state`. Settings renders that as a line of text or an install button.
@MainActor
@Observable
final class Updates: NSObject {
    static let shared = Updates()

    enum State: Equatable {
        case checking
        case upToDate
        case downloading(version: String)
        case readyToInstall(version: String)
        case installing
        /// The feed or the download could not be fetched; usually no network.
        case unreachable
    }

    /// The dev build is not in the appcast, and an update would replace it
    /// with the release, so it never checks.
    static let isDevBuild = Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true

    private(set) var state: State = .checking

    /// Install a downloaded update as soon as the app is idle, instead of
    /// waiting for the button in Settings. Sparkle owns the storage.
    var installsAutomatically: Bool {
        get { updater?.automaticallyDownloadsUpdates ?? false }
        set {
            updater?.automaticallyDownloadsUpdates = newValue
            if newValue { installWhenIdle() }
        }
    }

    @ObservationIgnored private var updater: SPUUpdater?
    @ObservationIgnored private let driver = SilentDriver()
    @ObservationIgnored private var idleTimer: Timer?

    private override init() {
        super.init()
        guard !Updates.isDevBuild else { return }
        driver.owner = self
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: nil)
        updater.automaticallyChecksForUpdates = true
        do {
            try updater.start()
            self.updater = updater
            updater.checkForUpdatesInBackground()
        } catch {
            Log.app.error("Updater failed to start: \(error.localizedDescription)")
            state = .unreachable
        }
    }

    /// Installs the downloaded update and relaunches. Does nothing unless an
    /// update is ready.
    func install() {
        guard case .readyToInstall = state, let reply = driver.installReply else { return }
        driver.installReply = nil
        state = .installing
        reply(.install)
    }

    /// Installs a ready update once no dictation is in flight, so the relaunch
    /// never cuts off a recording or a paste.
    fileprivate func installWhenIdle() {
        guard installsAutomatically, case .readyToInstall = state else { return }
        idleTimer?.invalidate()
        if Pipeline.shared.phase == .idle { install(); return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { _ in
            Task { @MainActor in Updates.shared.installWhenIdle() }
        }
    }

    fileprivate func set(_ state: State) { self.state = state }
}

/// The `SPUUserDriver` that answers Sparkle without a window. Every reply is
/// decided here except the final "install now", which waits for the user or
/// for the automatic-install timer.
@MainActor
private final class SilentDriver: NSObject, SPUUserDriver {
    weak var owner: Updates?
    var installReply: ((SPUUserUpdateChoice) -> Void)?

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        owner?.set(.checking)
    }

    func showUpdateFound(with item: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        let version = item.displayVersionString
        switch state.stage {
        case .notDownloaded, .downloaded:
            owner?.set(.downloading(version: version))
            reply(.install)
        case .installing:
            installReply = reply
            owner?.set(.readyToInstall(version: version))
            owner?.installWhenIdle()
        @unknown default:
            reply(.dismiss)
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        owner?.set(.upToDate)
        acknowledgement()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        Log.app.notice("Update check failed: \(error.localizedDescription)")
        owner?.set(.unreachable)
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {}
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() {}
    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        installReply = reply
        if case .downloading(let version) = owner?.state { owner?.set(.readyToInstall(version: version)) }
        owner?.installWhenIdle()
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        owner?.set(.installing)
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        installReply = nil
    }
}
