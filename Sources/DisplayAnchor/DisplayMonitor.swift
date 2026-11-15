import CoreGraphics
import Foundation
import os

/// Registers for CoreGraphics display-reconfiguration events, debounces the
/// flurry that a dock connect/disconnect produces, and reports a settled change
/// via `onDisplaysSettled`. Events caused by the app's own configuration writes
/// are ignored while any `performApplying` call is active.
@MainActor
final class DisplayMonitor {
    var onDisplaysSettled: (() -> Void)?
    /// Called when an external CoreGraphics reconfiguration finishes and stays idle briefly.
    var onReconfigurationCompleted: (() -> Void)?
    /// Called after the last overlapping `performApplying` suppression window closes.
    var onApplyFinished: (() -> Void)?
    /// Quiet period, in seconds, read when each change arrives. Values below 1 count as 1.
    var settleSeconds: @MainActor () -> Int = { 3 }
    /// Live active display IDs used to drop stale entries from `reconfiguringDisplays`.
    var activeDisplayIDs: () -> [CGDirectDisplayID] = DisplayEngine.activeDisplayIDs

    /// True while CoreGraphics has started configuring at least one display without finishing.
    var isReconfiguring: Bool { !reconfiguringDisplays.isEmpty }
    private(set) var reconfiguringDisplays: Set<CGDirectDisplayID> = []

    /// Number of `performApplying` calls whose suppression window is still open.
    private var activeApplyCount = 0
    private var debounceTask: Task<Void, Never>?
    private var reconfigurationTask: Task<Void, Never>?
    private var registered = false

    func start() {
        guard !registered else { return }
        let result = CGDisplayRegisterReconfigurationCallback(Self.callback, Unmanaged.passUnretained(self).toOpaque())
        registered = (result == .success)
    }

    /// Runs `work` with reconfiguration events suppressed and returns its result.
    /// Suppression lasts until one second after the last overlapping call returns.
    func performApplying<T>(_ work: () async -> T) async -> T {
        activeApplyCount += 1
        let result = await work()
        // CGCompleteDisplayConfiguration delivers late callbacks shortly after it returns.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            self.activeApplyCount -= 1
            if self.activeApplyCount == 0 {
                self.reconfigurationTask?.cancel()
                self.onApplyFinished?()
            }
        }
        return result
    }

    private static let callback: CGDisplayReconfigurationCallBack = { display, flags, userInfo in
        guard let userInfo else { return }
        let monitor = Unmanaged<DisplayMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        let raw = flags.rawValue
        Task { @MainActor in
            monitor.handleReconfiguration(
                display: display,
                flags: CGDisplayChangeSummaryFlags(rawValue: raw)
            )
        }
    }

    func handleReconfiguration(
        display: CGDirectDisplayID = kCGNullDirectDisplay,
        flags: CGDisplayChangeSummaryFlags
    ) {
        if flags.contains(.beginConfigurationFlag) {
            reconfiguringDisplays.formIntersection(Set(activeDisplayIDs()))
            if display != kCGNullDirectDisplay {
                reconfiguringDisplays.insert(display)
            }
            reconfigurationTask?.cancel()
            if activeApplyCount > 0 {
                Log.monitor.debug("reconfiguration ignored (own configuration change in progress)")
            } else {
                Log.monitor.debug("reconfiguration begin (ignored)")
            }
            return
        }

        reconfiguringDisplays.remove(display)
        reconfiguringDisplays.formIntersection(Set(activeDisplayIDs()))

        if activeApplyCount > 0 {
            Log.monitor.debug("reconfiguration ignored (own configuration change in progress)")
            return
        }

        Log.monitor.debug("reconfiguration flags=\(flags.rawValue)")
        if !isReconfiguring {
            scheduleReconfigurationCompleted()
        }
        scheduleSettledCheck()
    }

    private func scheduleReconfigurationCompleted() {
        reconfigurationTask?.cancel()
        reconfigurationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, !isReconfiguring, activeApplyCount == 0 else { return }
            Log.monitor.debug("reconfiguration completed")
            self.onReconfigurationCompleted?()
        }
    }

    /// Reports `onDisplaysSettled` after a quiet period, restarting any pending wait.
    func scheduleSettledCheck() {
        let quiet = max(1, settleSeconds())
        Log.monitor.debug("debounce \(quiet)s")
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(quiet))
            guard !Task.isCancelled else { return }
            Log.monitor.notice("displays settled (after \(quiet)s quiet)")
            self.onDisplaysSettled?()
        }
    }
}
