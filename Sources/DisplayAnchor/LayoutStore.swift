import AppKit
import Foundation
import MenuBarKit
import os

/// Central state and policy engine. Owns the reconfiguration monitor, the profile
/// store, and the notifier. Implements the manual-save / automatic-restore policy:
/// profiles are written only on explicit user action, while a debounced, settled
/// reconnect that matches a saved profile triggers an automatic restore.
@MainActor
final class LayoutStore: ObservableObject {
    enum MatchState: Equatable {
        case noDisplays
        case noSavedLayout
        case matches  // current set has a saved profile, and the layout matches it
        case differs  // current set has a saved profile, but the layout drifted
    }

    @Published private(set) var currentDisplays: [DisplaySnapshot] = []
    @Published private(set) var currentFingerprint = ""
    @Published private(set) var matchState: MatchState = .noDisplays
    @Published private(set) var lastRestoreLabel: String?
    @Published private(set) var lastRestoreAt: Date?
    @Published private(set) var justRestored = false
    @Published private(set) var autoRestoreSnoozedUntil: Date?
    /// True while a layout is being applied. Saves and further applies are ignored meanwhile.
    @Published private(set) var isApplying = false

    let config: AppConfig
    let profiles = ProfileStore()
    let notifier = Notifier()
    private let monitor = DisplayMonitor()

    var onStateChange: (() -> Void)?
    private var justRestoredTask: Task<Void, Never>?
    private var snoozeTask: Task<Void, Never>?

    init(config: AppConfig) {
        self.config = config
    }

    func start() {
        notifier.requestAuthorizationIfNeeded()
        monitor.settleSeconds = { [config] in config.settleSeconds }
        monitor.onDisplaysSettled = { [weak self] in self?.handleDisplaysSettled() }
        monitor.start()
        refreshCurrentState()
        // Displays configured before launch, as at login, send no further callback.
        monitor.scheduleSettledCheck()
    }

    // MARK: - Derived state

    var matchedProfile: LayoutProfile? { profiles.profile(for: currentFingerprint) }

    var savedProfiles: [LayoutProfile] {
        profiles.profiles.values.sorted { $0.savedAt > $1.savedAt }
    }

    var ambiguousIdentityKeys: Set<String> { DisplayEngine.ambiguousIdentityKeys(in: currentDisplays) }

    func refreshCurrentState() {
        let snapshot = DisplayEngine.snapshotCurrentLayout()
        currentDisplays = snapshot.displays
        currentFingerprint = snapshot.fingerprint
        if snapshot.displays.isEmpty {
            matchState = .noDisplays
        } else if let saved = profiles.profile(for: snapshot.fingerprint) {
            matchState =
                DisplayEngine.geometrySignature(snapshot) == DisplayEngine.geometrySignature(saved)
                ? .matches : .differs
        } else {
            matchState = .noSavedLayout
        }
        onStateChange?()
    }

    // MARK: - User actions

    @discardableResult
    func saveCurrentLayout(label: String) -> Bool {
        guard !isApplying else { return false }
        var snapshot = DisplayEngine.snapshotCurrentLayout()
        snapshot.label = label.trimmingCharacters(in: .whitespaces).isEmpty ? defaultLabel(for: snapshot) : label
        guard profiles.save(snapshot) else { return false }
        Log.restore.notice(
            "saveCurrentLayout: saved '\(snapshot.label, privacy: .public)' fp=\(snapshot.fingerprint, privacy: .public) displays=\(snapshot.displays.count)"
        )
        refreshCurrentState()
        return true
    }

    func defaultLabel(for profile: LayoutProfile) -> String {
        config.l("profile_default_label", config.localizer.displayCount(profile.displays.count))
    }

    func restoreNow() {
        guard let profile = matchedProfile else {
            Log.restore.notice(
                "restoreNow: no saved profile for current set (fp=\(self.currentFingerprint, privacy: .public)) → unmatched"
            )
            return
        }
        Log.restore.notice(
            "restoreNow: manual restore '\(profile.label, privacy: .public)' matchState=\(String(describing: self.matchState), privacy: .public)"
        )
        Task { await apply(profile, auto: false) }
    }

    func deleteProfile(fingerprint: String) {
        if profiles.delete(fingerprint: fingerprint) { refreshCurrentState() }
    }

    func rename(fingerprint: String, to label: String) {
        if profiles.rename(fingerprint: fingerprint, to: label) { refreshCurrentState() }
    }

    func diagnosticsText() -> String { DisplayEngine.diagnosticsText() }

    // MARK: - Interactive edits

    /// Makes `snapshot`'s display the main one, applied immediately. The relative
    /// arrangement is preserved (the engine re-anchors the new main to the origin).
    func setMainDisplay(_ snapshot: DisplaySnapshot) {
        guard !snapshot.isMain else { return }
        var displays = currentDisplays
        for index in displays.indices {
            displays[index].isMain = displays[index].stableID.snapshotKey == snapshot.stableID.snapshotKey
        }
        let profile = LayoutProfile(fingerprint: currentFingerprint, label: "", savedAt: Date(), displays: displays)
        Log.restore.notice("setMainDisplay: '\(snapshot.name, privacy: .public)'")
        performLiveChange(profile)
    }

    /// Rotates `snapshot`'s display to `degrees` (0/90/180/270), applied immediately.
    /// The other displays keep their modes and stay attached. A rotation the
    /// display rejects changes nothing.
    func rotateDisplay(_ snapshot: DisplaySnapshot, to degrees: Int) {
        let displays = LayoutEditing.rotating(
            currentDisplays, snapshotKey: snapshot.stableID.snapshotKey, to: degrees)
        let profile = LayoutProfile(fingerprint: currentFingerprint, label: "", savedAt: Date(), displays: displays)
        Log.restore.notice("rotateDisplay: '\(snapshot.name, privacy: .public)' → \(degrees)°")
        performLiveChange(profile, requireRotation: true)
    }

    /// Commits an edited draft layout to the system.
    func applyEditedLayout(_ draft: [DraftDisplay]) {
        let profile = LayoutEditing.profile(from: draft, base: currentDisplays, fingerprint: currentFingerprint)
        Log.restore.notice("applyEditedLayout: \(draft.count) displays")
        performLiveChange(profile)
    }

    /// Applies `profile` as a live edit with reconfiguration callbacks suppressed,
    /// flashing on success and re-reading state immediately and once more for
    /// changes that settle late. A successful change also pauses auto-restore.
    /// Ignored while another apply is in progress.
    private func performLiveChange(_ profile: LayoutProfile, requireRotation: Bool = false) {
        guard !isApplying else { return }
        isApplying = true
        Task {
            let result = await monitor.performApplying {
                await DisplayEngine.applyLayout(profile, requireRotation: requireRotation)
            }
            isApplying = false
            if case .applied = result {
                flashRestored()
                snoozeAfterManualChange()
            }
            refreshCurrentState()
            recheckIfDisplaySetChanged(since: profile)
            try? await Task.sleep(for: .seconds(1.2))
            refreshCurrentState()
        }
    }

    /// Schedules a settled check when the live display set is not the one `profile`
    /// was applied to: events that arrive during an apply are suppressed.
    private func recheckIfDisplaySetChanged(since profile: LayoutProfile) {
        if currentFingerprint != profile.fingerprint { monitor.scheduleSettledCheck() }
    }

    /// How long a pause of automatic restore lasts.
    static let autoRestorePauseDuration: TimeInterval = 15 * 60

    /// Pauses auto-restore after a manual live edit, notifying the user. An
    /// already-active snooze is extended silently.
    private func snoozeAfterManualChange() {
        guard config.autoRestoreEnabled else { return }
        let wasSnoozed = isAutoRestoreSnoozed
        snoozeAutoRestore(for: Self.autoRestorePauseDuration)
        guard !wasSnoozed else { return }
        notifier.send(
            title: config.l("notification_paused_title"),
            body: config.l("notification_paused_body", Int(Self.autoRestorePauseDuration / 60))
        )
    }

    // MARK: - Auto-restore snooze

    /// Whether auto-restore is currently paused by an unexpired snooze.
    var isAutoRestoreSnoozed: Bool {
        guard let until = autoRestoreSnoozedUntil else { return false }
        return until > Date()
    }

    /// Suspends automatic restore until `seconds` from now, after which it resumes
    /// on its own.
    func snoozeAutoRestore(for seconds: TimeInterval) {
        autoRestoreSnoozedUntil = Date().addingTimeInterval(seconds)
        Log.restore.notice("auto-restore snoozed for \(Int(seconds))s")
        onStateChange?()
        snoozeTask?.cancel()
        snoozeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            autoRestoreSnoozedUntil = nil
            Log.restore.notice("auto-restore snooze expired")
            onStateChange?()
        }
    }

    /// Cancels an active snooze and re-enables automatic restore immediately.
    func resumeAutoRestore() {
        snoozeTask?.cancel()
        autoRestoreSnoozedUntil = nil
        Log.restore.notice("auto-restore resumed manually")
        onStateChange?()
    }

    // MARK: - Reconnect handling

    private func handleDisplaysSettled() {
        refreshCurrentState()
        Log.restore.notice(
            "displaysSettled: fp=\(self.currentFingerprint, privacy: .public) matchState=\(String(describing: self.matchState), privacy: .public) autoRestore=\(self.config.autoRestoreEnabled)"
        )
        guard config.autoRestoreEnabled, let profile = matchedProfile else {
            Log.restore.debug("displaysSettled: auto-restore skipped (disabled or no saved profile)")
            return
        }
        if isAutoRestoreSnoozed {
            Log.restore.notice("displaysSettled: auto-restore skipped (snoozed)")
            return
        }
        guard matchState == .differs else {
            Log.restore.debug("displaysSettled: auto-restore skipped (already matches)")
            return
        }
        guard !isApplying else {
            Log.restore.notice("displaysSettled: auto-restore skipped (apply in progress)")
            return
        }
        Task { await apply(profile, auto: true) }
    }

    private func apply(_ profile: LayoutProfile, auto: Bool) async {
        guard !isApplying else { return }
        isApplying = true
        let result = await monitor.performApplying { await DisplayEngine.applyLayout(profile) }
        isApplying = false
        Log.restore.notice(
            "apply(auto: \(auto)): '\(profile.label, privacy: .public)' → \(String(describing: result), privacy: .public)"
        )

        switch result {
        case .applied:
            lastRestoreLabel = profile.label
            lastRestoreAt = Date()
            flashRestored()
            if config.notifyOnRestore {
                notifier.send(
                    title: config.l("notification_restored_title"),
                    body: config.l(
                        "notification_restored_body", profile.label,
                        config.localizer.displayCount(profile.displays.count))
                )
            }
        case .alreadyMatches:
            break
        case .unmatched:
            if auto {
                notifier.send(
                    title: config.l("notification_restore_failed_title"),
                    body: config.l("notification_unmatched_body", profile.label)
                )
            }
        case .failed:
            if auto {
                notifier.send(
                    title: config.l("notification_restore_failed_title"),
                    body: config.l("notification_rejected_body", profile.label)
                )
            }
        }

        refreshCurrentState()
        recheckIfDisplaySetChanged(since: profile)
    }

    private func flashRestored() {
        justRestored = true
        onStateChange?()
        justRestoredTask?.cancel()
        justRestoredTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            justRestored = false
            onStateChange?()
        }
    }
}
