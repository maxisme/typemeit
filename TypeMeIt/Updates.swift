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
/// Sparkle never shows its own windows here. With auto update on it checks on
/// launch and then on its hourly timer and downloads whatever it finds; off, it
/// checks only when Settings comes to the front and holds what it finds until
/// the install button. Either way it reports where it got to through `state`,
/// which Settings renders as a line of text or an install button.
@MainActor
@Observable
final class Updates: NSObject, SPUUpdaterDelegate {
    static let shared = Updates()

    enum State: Equatable {
        case checking
        case upToDate
        /// Found but not downloaded: auto update is off, and the version
        /// row's button is the only way on.
        case available(version: String)
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
    /// The version row's button was clicked on an `available` update, so the
    /// download it started installs as soon as it lands, whatever "ask before
    /// updating" says.
    @ObservationIgnored private var installRequested = false
    /// Ends a check that never comes back, so the row does not sit on
    /// "checking" when the feed is down.
    @ObservationIgnored private var checkTimeout: Task<Void, Never>?
    static let checkTimeoutSeconds: Double = 10

    private override init() {
        super.init()
        guard !Updates.isDevBuild else { return }
        driver.owner = self
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: self)
        let auto = Settings.shared.autoUpdate
        updater.automaticallyChecksForUpdates = auto
        // With auto update on every update is fetched in the background, and
        // "ask before updating" decides whether the install waits for a click.
        updater.automaticallyDownloadsUpdates = auto
        do {
            try updater.start()
            self.updater = updater
            if auto {
                updater.checkForUpdatesInBackground()
                armCheckTimeout()
            }
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
    /// front, so the row never shows a stale answer, and with auto update off
    /// the only time the feed is read. A found update, a download or an
    /// install in progress is left alone; a failed download is tried again.
    func checkNow() {
        guard let updater else { return }
        switch state {
        case .checking, .upToDate, .unreachable, .downloadFailed: break
        case .available, .downloading, .readyToInstall, .installing: return
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

    /// Installs the update and relaunches. An update that is only found is
    /// downloaded first and installs as soon as it lands. Does nothing unless
    /// an update is found or ready.
    func install() {
        switch state {
        case .available:
            guard driver.foundReply != nil else { return }
            installRequested = true
            download()
        case .readyToInstall:
            guard let reply = driver.installReply else { return }
            driver.installReply = nil
            state = .installing
            reply(.install)
        default:
            return
        }
    }

    /// Answers a held `available` update: Sparkle downloads it and comes back
    /// through the driver's `showReady`.
    private func download() {
        guard case .available(let version) = state, let reply = driver.foundReply else { return }
        driver.foundReply = nil
        set(.downloading(version: version))
        reply(.install)
    }

    /// A ready update installs itself when the version row asked for it, or
    /// when auto update is on and the app is not to ask first.
    private var installsUnattended: Bool {
        installRequested || (Settings.shared.autoUpdate && !Settings.shared.askBeforeUpdating)
    }

    /// The pill only announces an update the app fetched on its own.
    private var announcesReady: Bool {
        !installRequested && Settings.shared.autoUpdate && Settings.shared.askBeforeUpdating
    }

    /// Installs a ready update once no dictation is in flight, so the relaunch
    /// never cuts off a recording or a paste.
    fileprivate func installWhenIdle() {
        guard installsUnattended, case .readyToInstall = state else { return }
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
            if announcesReady { announce(version, toast: .updateReady(version: version)) }
        case .downloadFailed(let version):
            AppState.shared.updateReady = nil
            installRequested = false
            announce(version, toast: .updateFailed(version: version))
        default:
            AppState.shared.updateReady = nil
        }
    }

    /// The pipeline is idle again: a ready update the user has not put off
    /// goes back on screen, since a recording takes the pill down.
    func remind() {
        guard announcesReady, case .readyToInstall(let version) = state else { return }
        announce(version, toast: .updateReady(version: version))
    }

    /// The pill's cross: the update stays in the menu and in Settings, but
    /// the pill does not come back for this version.
    func putOff(_ version: String) {
        announced.insert(version)
    }

    /// A setting was switched. Auto update on fetches a found update and puts
    /// Sparkle's hourly check back; off takes the check away. Then a ready
    /// update either goes back on the pill or installs as soon as the app is
    /// idle, whichever the settings now say.
    func preferencesChanged() {
        let auto = Settings.shared.autoUpdate
        updater?.automaticallyChecksForUpdates = auto
        updater?.automaticallyDownloadsUpdates = auto
        if auto { download() }
        remind()
        installWhenIdle()
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
/// for the automatic-install timer, and with auto update off the first
/// "download it", which waits for the user.
@MainActor
private final class SilentDriver: NSObject, SPUUserDriver {
    weak var owner: Updates?
    var installReply: ((SPUUserUpdateChoice) -> Void)?
    var foundReply: ((SPUUserUpdateChoice) -> Void)?

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: Settings.shared.autoUpdate, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        owner?.set(.checking)
    }

    func showUpdateFound(with item: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        let version = item.displayVersionString
        switch state.stage {
        case .notDownloaded where !Settings.shared.autoUpdate:
            foundReply = reply
            owner?.set(.available(version: version))
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
        foundReply = nil
    }
}
