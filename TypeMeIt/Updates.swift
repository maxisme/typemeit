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
final class Updates: NSObject, SPUUpdaterDelegate {
    static let shared = Updates()

    enum State: Equatable {
        case checking
        case upToDate
        case downloading(version: String)
        case readyToInstall(version: String)
        case installing
        /// The feed could not be fetched; usually no network.
        case unreachable
        /// An update was found but its download failed. Sparkle tries again on the next check.
        case downloadFailed(version: String)
    }

    /// The dev build is not in the appcast, and an update would replace it
    /// with the release, so it never checks.
    static let isDevBuild = Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true

    private(set) var state: State = .checking

    @ObservationIgnored private var updater: SPUUpdater?
    @ObservationIgnored private let driver = SilentDriver()
    @ObservationIgnored private var idleTimer: Timer?
    /// Versions whose toast is not to come back: a failed download is told
    /// once, a ready update once the user has put it off.
    @ObservationIgnored private var announced: Set<String> = []
    @ObservationIgnored private var retry: Timer?
    /// Ends a check that never comes back, so the row does not sit on
    /// "checking" when the feed is down.
    @ObservationIgnored private var checkTimeout: Task<Void, Never>?
    static let checkTimeoutSeconds: Double = 10

    private override init() {
        super.init()
        guard !Updates.isDevBuild else { return }
        driver.owner = self
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: self)
        updater.automaticallyChecksForUpdates = true
        // Always fetched in the background; the setting decides whether the
        // install waits for a click.
        updater.automaticallyDownloadsUpdates = true
        do {
            try updater.start()
            self.updater = updater
            updater.checkForUpdatesInBackground()
            armCheckTimeout()
        } catch {
            Log.app.error("Updater failed to start: \(error.localizedDescription)")
            state = .unreachable
        }
    }

    /// Sparkle tells the user driver about updates it finds, but a background
    /// check that finds nothing ends silently; only the delegate hears about
    /// it. Without this the status would say "checking" forever.
    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        let outcome: State? = if let error {
            (error as NSError).domain == SUSparkleErrorDomain && (error as NSError).code == SUError.noUpdateError.rawValue ? .upToDate : nil
        } else { nil }
        Task { @MainActor in
            guard case .checking = self.state else { return }
            if let outcome { self.set(outcome) } else if error != nil { self.set(.unreachable) } else { self.set(.upToDate) }
        }
    }

    /// With automatic updates on, Sparkle downloads and stages the update without
    /// telling the user driver, then waits for the app to quit. Taking over here
    /// puts the install button in Settings and lets the idle timer relaunch.
    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping @Sendable () -> Void) -> Bool {
        let version = item.displayVersionString
        MainActor.assumeIsolated {
            driver.installReply = { _ in immediateInstallHandler() }
            set(.readyToInstall(version: version))
            installWhenIdle()
        }
        return true
    }

    /// Checks the feed again. Called when the settings window comes to the
    /// front, so the row never shows a stale answer. A download or install
    /// in progress is left alone.
    func checkNow() {
        guard let updater else { return }
        switch state {
        case .checking, .upToDate, .unreachable: break
        case .downloading, .readyToInstall, .installing, .downloadFailed: return
        }
        guard updater.canCheckForUpdates else { return }
        set(.checking)
        updater.checkForUpdatesInBackground()
        armCheckTimeout()
    }

    /// A check still running after `checkTimeoutSeconds` is treated as
    /// unreachable. A late answer is dropped by the delegate's guard, and the
    /// next focus asks again.
    private func armCheckTimeout() {
        checkTimeout?.cancel()
        checkTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Updates.checkTimeoutSeconds))
            guard !Task.isCancelled, let self, case .checking = self.state else { return }
            Log.app.notice("Update check timed out")
            self.set(.unreachable)
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
        guard !Settings.shared.askBeforeUpdating, case .readyToInstall = state else { return }
        idleTimer?.invalidate()
        if Pipeline.shared.phase == .idle { install(); return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { _ in
            Task { @MainActor in Updates.shared.installWhenIdle() }
        }
    }

    fileprivate func set(_ state: State) {
        self.state = state
        if case .checking = state {} else { checkTimeout?.cancel() }
        switch state {
        case .readyToInstall(let version):
            AppState.shared.updateReady = version
            if Settings.shared.askBeforeUpdating { announce(version, toast: .updateReady(version: version)) }
        case .downloadFailed(let version):
            AppState.shared.updateReady = nil
            announce(version, toast: .updateFailed(version: version))
        default:
            AppState.shared.updateReady = nil
        }
    }

    /// The pipeline is idle again: a ready update the user has not put off
    /// goes back on screen, since a recording takes the pill down.
    func remind() {
        guard Settings.shared.askBeforeUpdating, case .readyToInstall(let version) = state else { return }
        announce(version, toast: .updateReady(version: version))
    }

    /// The pill's cross: the update stays in the menu and in Settings, but
    /// the pill does not come back for this version.
    func putOff(_ version: String) {
        announced.insert(version)
    }

    /// The setting was switched: on, the pill comes up for a waiting update;
    /// off, it installs as soon as the app is idle.
    func askPreferenceChanged() {
        if Settings.shared.askBeforeUpdating { remind() } else { installWhenIdle() }
    }

    /// Shows a toast for `version`, waiting for a moment when nothing else is
    /// on screen. One retry at a time, so a reminder on every idle does not
    /// stack timers.
    private func announce(_ version: String, toast: OverlayModel.State) {
        guard !announced.contains(version) else { return }
        retry?.invalidate()
        if Pipeline.shared.showToast(toast) {
            if case .updateReady = toast {} else { announced.insert(version) }
            return
        }
        retry = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { _ in
            Task { @MainActor in
                guard Updates.shared.state == Updates.shared.stateMatching(toast) else { return }
                Updates.shared.announce(version, toast: toast)
            }
        }
    }

    /// The updater state a toast belongs to, so a stale retry is dropped.
    private func stateMatching(_ toast: OverlayModel.State) -> State {
        switch toast {
        case .updateReady(let v): .readyToInstall(version: v)
        case .updateFailed(let v): .downloadFailed(version: v)
        default: .checking
        }
    }
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
        Log.app.notice("Update failed: \(error.localizedDescription)")
        if case .downloading(let version) = owner?.state {
            owner?.set(.downloadFailed(version: version))
        } else {
            owner?.set(.unreachable)
        }
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
