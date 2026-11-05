import Combine
import Foundation
import Sparkle

/// Publishes channel-filtered update state and starts installation on request.
/// Checks are silent; unbundled runs have no updater.
@MainActor
final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    /// Repository behind the update feed, and the project page linked from settings.
    static let repository = "gabriarceus/DisplayAnchor"

    /// Public page of the repository.
    static let repositoryURL = URL(string: "https://github.com/\(repository)")!

    static let releasesURL = repositoryURL.appendingPathComponent("releases")

    private static let announcedVersionKey = "announcedUpdateVersion"

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(String)
        case failed
    }

    @Published private(set) var status: Status = .idle

    /// Version of the running bundle. Unbundled runs have no Info.plist, so they
    /// report 0.0.0.
    let currentVersion: String

    private let config: AppConfig
    private let defaults = UserDefaults.standard
    private var userDriver: DeferredUpdateUserDriver?
    private var updater: SPUUpdater?
    /// True after a channel change until a check of the new channel starts.
    /// Results and offers that arrive meanwhile belong to the old channel and are ignored.
    private var needsChannelCheck = false

    init(config: AppConfig, updater: SPUUpdater? = nil) {
        self.config = config
        self.updater = updater
        currentVersion =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.0.0"
        super.init()
    }

    /// Version of the pending update, if the last check found one.
    var availableVersion: String? {
        if case .available(let version) = status { return version }
        return nil
    }

    /// Whether a check can be started. False while a session is running and
    /// outside a bundle, where there is no updater at all.
    var canCheck: Bool {
        guard let updater else { return false }
        return updater.canCheckForUpdates && !updater.sessionInProgress
    }

    /// Creates and starts the updater, then checks the feed once without UI.
    /// Does nothing outside an app bundle; a start failure is logged and leaves
    /// the app without an updater.
    func start() {
        guard updater == nil, Bundle.main.bundleURL.pathExtension == "app" else { return }
        // Built by hand instead of with SPUStandardUpdaterController, which reports a
        // misconfigured feed with a modal alert. The updater is created here, not in
        // init, because it needs `self` as its delegate.
        let userDriver = DeferredUpdateUserDriver(config: config) { [weak self] in
            self?.needsChannelCheck == false
        }
        let updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: userDriver,
            delegate: self
        )
        updater.automaticallyChecksForUpdates = config.checkForUpdates
        do {
            try updater.start()
        } catch {
            Log.updates.error(
                "Updater not started: \(error.localizedDescription, privacy: .public)")
            return
        }
        self.userDriver = userDriver
        self.updater = updater
        probe(manual: false)
    }

    /// Checks the feed now and reports the result in `status`, without a Sparkle window.
    func checkNow() {
        probe(manual: true)
    }

    /// Shows the available update in Sparkle's update window, where the user
    /// chooses to install it, skip it, or be reminded later.
    func install() {
        updater?.checkForUpdates()
    }

    /// Mirrors the settings toggle onto Sparkle's own scheduling.
    func setAutomaticChecks(_ enabled: Bool) {
        updater?.automaticallyChecksForUpdates = enabled
        if enabled { probe(manual: false) }
    }

    /// Clears the status and any held offer, then checks the newly selected
    /// channel as soon as no update session is running.
    func updateChannelChanged() {
        status = .idle
        needsChannelCheck = true
        userDriver?.dismissPendingUpdate()
        checkSelectedChannelIfPossible()
    }

    private func checkSelectedChannelIfPossible() {
        guard needsChannelCheck, canCheck else { return }
        needsChannelCheck = false
        probe(manual: true)
    }

    /// Silent feed check: shows no UI of its own and only drives the delegate
    /// callbacks below. A background probe leaves `status` alone until it has an
    /// answer, so a pending update does not flicker away while re-checking.
    private func probe(manual: Bool) {
        guard let updater, canCheck else { return }
        guard manual || config.checkForUpdates else { return }
        if manual { status = .checking }
        updater.checkForUpdateInformation()
    }

    /// The pending version if it has not been announced yet, and marks it as
    /// announced. Returns nil for a version that was already announced.
    func consumeUnannouncedUpdate() -> String? {
        guard let version = availableVersion,
            defaults.string(forKey: Self.announcedVersionKey) != version
        else { return nil }
        defaults.set(version, forKey: Self.announcedVersionKey)
        return version
    }

    // MARK: - SPUUpdaterDelegate

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        config.updateChannel.allowedChannels
    }

    // Release notes are embedded in the feed, so there is nothing to download.
    func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate updateItem: SUAppcastItem) -> Bool {
        false
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        Task { @MainActor [weak self] in
            self?.checkSelectedChannelIfPossible()
        }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        guard !needsChannelCheck, config.updateChannel.allows(item.channel) else { return }
        Log.updates.info("Update available: \(item.displayVersionString, privacy: .public)")
        status = .available(item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        guard !needsChannelCheck else { return }
        status = .upToDate
        defaults.removeObject(forKey: Self.announcedVersionKey)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        guard !needsChannelCheck else { return }
        let nsError = error as NSError
        guard
            nsError.domain != SUSparkleErrorDomain
                || nsError.code != Int(SUError.noUpdateError.rawValue)
        else {
            return
        }
        Log.updates.error("Update check failed: \(error.localizedDescription, privacy: .public)")
        // Losing the network says nothing about a known pending update.
        if availableVersion == nil { status = .failed }
    }
}
