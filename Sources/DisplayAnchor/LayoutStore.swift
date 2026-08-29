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
        case matches        // current set has a saved profile, and the layout matches it
        case differs        // current set has a saved profile, but the layout drifted
    }

    @Published private(set) var currentDisplays: [DisplaySnapshot] = []
    @Published private(set) var currentFingerprint = ""
    @Published private(set) var matchState: MatchState = .noDisplays
    @Published private(set) var lastRestoreLabel: String?
    @Published private(set) var lastRestoreAt: Date?
    @Published private(set) var justRestored = false
    @Published private(set) var autoRestoreSnoozedUntil: Date?

    let config: AppConfig
    let profiles = ProfileStore()
    let notifier = Notifier()
    private let monitor = DisplayMonitor()

    var onStateChange: (() -> Void)?
    private var justRestoredTask: Task<Void, Never>?
    private var snoozeTask: Task<Void, Never>?
    private var modeRestoreTask: Task<Void, Never>?

    init(config: AppConfig) {
        self.config = config
    }

    func start() {
        notifier.requestAuthorizationIfNeeded()
        monitor.settleSeconds = max(1, config.settleSeconds)
        monitor.onDisplaysSettled = { [weak self] in self?.handleDisplaysSettled() }
        monitor.start()
        refreshCurrentState()
    }

    /// Re-read the live monitor configuration after settings change.
    func applySettings() {
        monitor.settleSeconds = max(1, config.settleSeconds)
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
            matchState = DisplayEngine.geometrySignature(snapshot) == DisplayEngine.geometrySignature(saved) ? .matches : .differs
        } else {
            matchState = .noSavedLayout
        }
        onStateChange?()
    }

    // MARK: - User actions

    @discardableResult
    func saveCurrentLayout(label: String) -> Bool {
        var snapshot = DisplayEngine.snapshotCurrentLayout()
        snapshot.label = label.trimmingCharacters(in: .whitespaces).isEmpty ? defaultLabel(for: snapshot) : label
        guard profiles.save(snapshot) else { return false }
        Log.restore.notice("saveCurrentLayout: saved '\(snapshot.label, privacy: .public)' fp=\(snapshot.fingerprint, privacy: .public) displays=\(snapshot.displays.count)")
        refreshCurrentState()
        return true
    }

    func defaultLabel(for profile: LayoutProfile) -> String {
        config.l("profile_default_label", displayCountText(profile))
    }

    func restoreNow() {
        guard let profile = matchedProfile else {
            Log.restore.notice("restoreNow: no saved profile for current set (fp=\(self.currentFingerprint, privacy: .public)) → unmatched")
            return
        }
        Log.restore.notice("restoreNow: manual restore '\(profile.label, privacy: .public)' matchState=\(String(describing: self.matchState), privacy: .public)")
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
            displays[index].isMain = displays[index].stableID.identityKey == snapshot.stableID.identityKey
        }
        let profile = LayoutProfile(fingerprint: currentFingerprint, label: "", savedAt: Date(), displays: displays)
        Log.restore.notice("setMainDisplay: '\(snapshot.name, privacy: .public)'")
        Task { await performLiveChange { await DisplayEngine.applyLayout(profile) } }
    }

    /// Rotates `snapshot`'s display to `degrees` (0/90/180/270), applied immediately.
    /// The framebuffer transform resets the display to a default mode, so once the
    /// rotation settles the pre-rotation mode is re-applied.
    func rotateDisplay(_ snapshot: DisplaySnapshot, to degrees: Int) {
        guard let id = DisplayEngine.liveID(for: snapshot) else {
            Log.restore.notice("rotateDisplay: no live match for '\(snapshot.name, privacy: .public)'")
            return
        }
        Log.restore.notice("rotateDisplay: '\(snapshot.name, privacy: .public)' → \(degrees)°")
        modeRestoreTask?.cancel()
        Task {
            let result = await performLiveChange { DisplayEngine.setRotation(id, degrees: degrees) ? .applied : .failed("rotation rejected") }
            guard result == .applied else { return }

            modeRestoreTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                let restored = await self.performLiveChange { DisplayEngine.setMode(id, to: snapshot.mode) }
                Log.restore.notice("rotateDisplay: mode restore → \(String(describing: restored), privacy: .public)")
            }
        }
    }

    /// Commits an edited draft layout to the system.
    func applyEditedLayout(_ draft: [DraftDisplay]) {
        let profile = LayoutEditing.profile(from: draft, base: currentDisplays, fingerprint: currentFingerprint)
        Log.restore.notice("applyEditedLayout: \(draft.count) displays")
        Task { await performLiveChange { await DisplayEngine.applyLayout(profile) } }
    }

    /// Runs a live display mutation with reconfiguration callbacks suppressed
    /// (so it can't trigger an auto-restore), flashing on success and re-reading
    /// state immediately and again once changes that settle late (rotation) land.
    /// A successful change also pauses auto-restore so it won't undo the edit.
    @discardableResult
    private func performLiveChange(_ work: () async -> LayoutApplyResult) async -> LayoutApplyResult {
        let result = await monitor.performApplying(work)
        if case .applied = result {
            flashRestored()
            snoozeAfterManualChange()
        }
        refreshCurrentState()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            self.refreshCurrentState()
        }
        return result
    }

    private static let manualChangeSnoozeSeconds: TimeInterval = 15 * 60

    /// Pauses auto-restore after a manual live edit, notifying the user. An
    /// already-active snooze is extended silently, so a single user action that
    /// lands in several steps (e.g. rotation + mode restore) notifies only once.
    private func snoozeAfterManualChange() {
        guard config.autoRestoreEnabled else { return }
        let wasSnoozed = isAutoRestoreSnoozed
        snoozeAutoRestore(for: Self.manualChangeSnoozeSeconds)
        guard !wasSnoozed else { return }
        notifier.send(
            title: config.l("notification_paused_title"),
            body: config.l("notification_paused_body", Int(Self.manualChangeSnoozeSeconds / 60))
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
        Log.restore.notice("displaysSettled: fp=\(self.currentFingerprint, privacy: .public) matchState=\(String(describing: self.matchState), privacy: .public) autoRestore=\(self.config.autoRestoreEnabled)")
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
        Task { await apply(profile, auto: true) }
    }

    private func apply(_ profile: LayoutProfile, auto: Bool) async {
        modeRestoreTask?.cancel()
        let result = await monitor.performApplying { await DisplayEngine.applyLayout(profile) }
        Log.restore.notice("apply(auto: \(auto)): '\(profile.label, privacy: .public)' → \(String(describing: result), privacy: .public)")

        switch result {
        case .applied:
            lastRestoreLabel = profile.label
            lastRestoreAt = Date()
            flashRestored()
            if config.notifyOnRestore {
                notifier.send(
                    title: config.l("notification_restored_title"),
                    body: config.l("notification_restored_body", profile.label, displayCountText(profile))
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
    }

    private func displayCountText(_ profile: LayoutProfile) -> String {
        let count = profile.displays.count
        return count == 1 ? config.l("display_count_one", count) : config.l("display_count_other", count)
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
