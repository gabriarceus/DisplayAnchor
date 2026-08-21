import Combine
import Foundation
import Sparkle

/// Update pipeline backed by Sparkle, wired so the app keeps its own
/// affordances instead of Sparkle's scheduled-reminder window: a silent feed
/// check publishes [status] — which drives the menu bar dot, the settings row
/// and the notification — and Sparkle's standard flow (alert, download,
/// install, relaunch) is entered only when the user asks for it via [install].
///
/// Everything no-ops outside a .app bundle: Sparkle reads the feed URL and the
/// public key from Info.plist, which `swift run` does not have.
@MainActor
final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate,
    @preconcurrency SPUStandardUserDriverDelegate
{
    /// Repository behind the update feed, and the project page linked from settings.
    static let repository = "gabriarceus/DisplayAnchor"

    /// Public page of the repository.
    static let repositoryURL = URL(string: "https://github.com/\(repository)")!

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
    private var userDriver: SPUStandardUserDriver?
    private var updater: SPUUpdater?

    init(config: AppConfig) {
        self.config = config
        currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        super.init()
    }

    /// Version of the pending update, if the last check found one.
    var availableVersion: String? {
        if case .available(let version) = status { return version }
        return nil
    }

    /// Whether a check can be started. False while a session is running and
    /// outside a bundle, where there is no updater at all.
    var canCheck: Bool { updater?.canCheckForUpdates ?? false }

    /// Builds the updater — deferred out of `init` so it can be its own delegate
    /// — starts Sparkle's scheduled cycle, and probes the feed once so a pending
    /// update is known without waiting for the first scheduled check.
    ///
    /// Assembled by hand rather than through `SPUStandardUpdaterController`: that
    /// wrapper reports a misconfigured feed with a modal alert, which an app with
    /// no windows should never raise. Here the failure is logged and the app runs
    /// on without an updater.
    func start() {
        guard updater == nil, Bundle.main.bundleURL.pathExtension == "app" else { return }
        let userDriver = SPUStandardUserDriver(hostBundle: .main, delegate: self)
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
            Log.updates.error("Updater not started: \(error.localizedDescription, privacy: .public)")
            return
        }
        self.userDriver = userDriver
        self.updater = updater
        probe(manual: false)
    }

    /// User-initiated check. Reports its outcome in the settings row rather than
    /// in a Sparkle window, so the settings screen stays the single surface.
    func checkNow() {
        probe(manual: true)
    }

    /// Hands over to Sparkle: release notes, download, install and relaunch are
    /// its standard flow, and re-checking the feed is part of it.
    func install() {
        updater?.checkForUpdates()
    }

    /// Mirrors the settings toggle onto Sparkle's own scheduling.
    func setAutomaticChecks(_ enabled: Bool) {
        updater?.automaticallyChecksForUpdates = enabled
        if enabled { probe(manual: false) }
    }

    /// Silent feed check: shows no UI of its own and only drives the delegate
    /// callbacks below. A background probe leaves [status] alone until it has an
    /// answer, so a pending update does not flicker away while re-checking.
    private func probe(manual: Bool) {
        guard let updater, updater.canCheckForUpdates else { return }
        guard manual || config.checkForUpdates else { return }
        if manual { status = .checking }
        updater.checkForUpdateInformation()
    }

    /// The pending version if it has not been announced yet, marking it
    /// announced in the same step. Announcing once per version keeps a schedule
    /// that re-checks for as long as the app runs from repeating the alert.
    func consumeUnannouncedUpdate() -> String? {
        guard let version = availableVersion,
              defaults.string(forKey: Self.announcedVersionKey) != version
        else { return nil }
        defaults.set(version, forKey: Self.announcedVersionKey)
        return version
    }

    // MARK: - SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Log.updates.info("Update available: \(item.displayVersionString, privacy: .public)")
        status = .available(item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        status = .upToDate
        defaults.removeObject(forKey: Self.announcedVersionKey)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        Log.updates.error("Update check failed: \(error.localizedDescription, privacy: .public)")
        // Losing the network says nothing about a known pending update.
        if availableVersion == nil { status = .failed }
    }

    // MARK: - SPUStandardUserDriverDelegate

    /// The menu bar dot and the notification are the reminder, so Sparkle must
    /// not open its window on its own schedule.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }
}
