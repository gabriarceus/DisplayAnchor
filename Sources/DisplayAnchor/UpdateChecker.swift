import AppKit
import Combine
import Foundation

/// A dotted version, parsed leniently from release tags ("v1.2.3") and from
/// Info.plist strings ("1.2"). Any pre-release or build suffix is dropped:
/// GitHub's `releases/latest` never points at a pre-release, so what remains
/// is always a plain release number.
struct AppVersion: Comparable {
    private let parts: [Int]

    init?(_ raw: String) {
        var core = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if core.first == "v" || core.first == "V" { core.removeFirst() }
        core = String(core.prefix { $0.isNumber || $0 == "." })
        let parts = core.split(separator: ".").compactMap { Int($0) }
        guard !parts.isEmpty else { return nil }
        self.parts = parts
    }

    /// Component-wise comparison, treating missing components as zero so that
    /// "1.2" and "1.2.0" compare equal.
    private static func component(_ version: AppVersion, _ index: Int) -> Int {
        index < version.parts.count ? version.parts[index] : 0
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let left = component(lhs, index)
            let right = component(rhs, index)
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (0..<max(lhs.parts.count, rhs.parts.count)).allSatisfy {
            component(lhs, $0) == component(rhs, $0)
        }
    }
}

/// Update notifier backed by the repository's GitHub Releases.
///
/// The app is distributed as a zip attached to a GitHub Release, so the newest
/// published tag is the source of truth: this polls `releases/latest`, compares
/// it with the running bundle's `CFBundleShortVersionString` and — when a newer
/// version exists — points the user at the release page. It never downloads or
/// installs anything; without a Developer ID signature an in-app installer
/// would have to strip quarantine and swap the bundle itself, which is a much
/// larger surface than a link.
///
/// A found update is remembered across launches, so the pending state survives
/// the daily gate, and is offered for announcement exactly once per version
/// through [consumeUnannouncedUpdate].
@MainActor
final class UpdateChecker: ObservableObject {
    /// Repository whose releases are the update source.
    static let repository = "gabriarceus/DisplayAnchor"

    /// Public page of the repository.
    static let repositoryURL = URL(string: "https://github.com/\(repository)")!

    private static let checkInterval: TimeInterval = 24 * 60 * 60
    /// How often the background schedule re-evaluates the gate. Shorter than
    /// [checkInterval] so a session that spans a release does not have to wait
    /// for a full day past the gate's expiry.
    private static let pollInterval: TimeInterval = 6 * 60 * 60
    private static let lastCheckKey = "lastUpdateCheck"
    private static let pendingVersionKey = "pendingUpdateVersion"
    private static let pendingPageURLKey = "pendingUpdatePageURL"
    private static let announcedVersionKey = "announcedUpdateVersion"

    struct Update: Equatable {
        let version: String
        let pageURL: URL
    }

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(Update)
        case failed
    }

    @Published private(set) var status: Status = .idle

    /// Version of the running bundle. Unbundled runs (`swift run`) have no
    /// Info.plist, so they report 0.0.0 and every release reads as newer.
    let currentVersion: String

    private let config: AppConfig
    private let defaults = UserDefaults.standard
    private let session: URLSession
    private var inFlight: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    init(config: AppConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
        currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        restorePendingUpdate()
    }

    /// The pending update, if the last check found one.
    var availableUpdate: Update? {
        if case .available(let update) = status { return update }
        return nil
    }

    /// Starts the background schedule: a due-check now, one every [pollInterval]
    /// and one on wake. The periodic task alone is not enough — a Mac that sleeps
    /// through the interval would otherwise wait for the next full tick after
    /// the lid opens. Repeated calls are ignored.
    func start() {
        guard pollTask == nil else { return }
        checkIfDue()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.pollInterval))
                guard !Task.isCancelled else { return }
                self?.checkIfDue()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue() }
        }
    }

    /// Background check, at most once per [checkInterval] and only while the
    /// user has automatic checks on. Failures stay silent (no network on a
    /// laptop lid-open is not something to report), and a no-update result
    /// leaves the UI in `.idle` rather than announcing itself.
    func checkIfDue() {
        guard config.checkForUpdates else { return }
        if let last = defaults.object(forKey: Self.lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < Self.checkInterval {
            return
        }
        check(manual: false)
    }

    /// User-initiated check: always hits the network and surfaces the outcome.
    func checkNow() {
        check(manual: true)
    }

    private func check(manual: Bool) {
        guard inFlight == nil else { return }
        if manual { status = .checking }

        inFlight = Task { [weak self] in
            guard let self else { return }
            defer { self.inFlight = nil }
            do {
                let release = try await self.fetchLatestRelease()
                self.defaults.set(Date(), forKey: Self.lastCheckKey)
                if let release {
                    self.resolve(release, manual: manual)
                } else {
                    // No release published: nothing to download, so from the
                    // user's side this is indistinguishable from being current.
                    self.clearPendingUpdate()
                    self.status = manual ? .upToDate : .idle
                }
            } catch {
                Log.updates.error("Update check failed: \(error.localizedDescription, privacy: .public)")
                // An unreachable network says nothing about a known pending
                // update, so keep advertising it.
                if manual {
                    self.status = .failed
                } else if self.availableUpdate == nil {
                    self.status = .idle
                }
            }
        }
    }

    private func resolve(_ release: Release, manual: Bool) {
        guard let latest = AppVersion(release.tagName), let current = AppVersion(currentVersion) else {
            Log.updates.error("Unparsable version (tag \(release.tagName, privacy: .public), bundle \(self.currentVersion, privacy: .public))")
            status = manual ? .failed : .idle
            return
        }
        if latest > current {
            Log.updates.info("Update available: \(release.tagName, privacy: .public)")
            let update = Update(version: release.displayVersion, pageURL: release.htmlURL)
            storePendingUpdate(update)
            // A manual check reports the result on screen, so it needs no banner.
            if manual { markAnnounced(update) }
            status = .available(update)
        } else {
            clearPendingUpdate()
            status = manual ? .upToDate : .idle
        }
    }

    // MARK: - Pending update persistence

    /// Re-publishes the update found by an earlier run. Without this the menu
    /// bar and the settings screen would look up to date after every relaunch
    /// until the gate lets a fresh check through. A remembered version that is
    /// no longer newer (the user installed it) is discarded.
    private func restorePendingUpdate() {
        guard let version = defaults.string(forKey: Self.pendingVersionKey),
              let pageURL = defaults.url(forKey: Self.pendingPageURLKey),
              let pending = AppVersion(version),
              let current = AppVersion(currentVersion),
              pending > current
        else {
            clearPendingUpdate()
            return
        }
        status = .available(Update(version: version, pageURL: pageURL))
    }

    private func storePendingUpdate(_ update: Update) {
        defaults.set(update.version, forKey: Self.pendingVersionKey)
        defaults.set(update.pageURL, forKey: Self.pendingPageURLKey)
    }

    private func clearPendingUpdate() {
        defaults.removeObject(forKey: Self.pendingVersionKey)
        defaults.removeObject(forKey: Self.pendingPageURLKey)
        defaults.removeObject(forKey: Self.announcedVersionKey)
    }

    /// The pending update if it has not been announced yet, marking it announced
    /// in the same step. Announcing once per version keeps a schedule that
    /// re-checks for as long as the app runs from repeating the same alert.
    func consumeUnannouncedUpdate() -> Update? {
        guard let update = availableUpdate,
              defaults.string(forKey: Self.announcedVersionKey) != update.version
        else { return nil }
        markAnnounced(update)
        return update
    }

    private func markAnnounced(_ update: Update) {
        defaults.set(update.version, forKey: Self.announcedVersionKey)
    }

    /// The newest published release, or nil when the repository has none yet.
    private func fetchLatestRelease() async throws -> Release? {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 15
        // A cached 200 would make a manual "Check Now" a no-op right after a release.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateError.malformedResponse }
        if http.statusCode == 404 { return nil }
        // 403/429 = unauthenticated rate limit (60 requests/hour per IP — far
        // above a daily check, but shared NATs exist).
        guard http.statusCode == 200 else { throw UpdateError.http(http.statusCode) }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: URL

        /// Tag without the conventional "v" prefix, for display next to the
        /// bundle version (which never carries one).
        var displayVersion: String {
            tagName.first == "v" || tagName.first == "V" ? String(tagName.dropFirst()) : tagName
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    private enum UpdateError: LocalizedError {
        case malformedResponse
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .malformedResponse: "malformed response"
            case .http(let code): "HTTP \(code)"
            }
        }
    }
}
