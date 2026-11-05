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
    var settleSeconds: Int = 3

    /// Number of `performApplying` calls whose suppression window is still open.
    private var activeApplyCount = 0
    private var debounceTask: Task<Void, Never>?
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
        }
        return result
    }

    private static let callback: CGDisplayReconfigurationCallBack = { _, flags, userInfo in
        guard let userInfo else { return }
        let monitor = Unmanaged<DisplayMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        let raw = flags.rawValue
        Task { @MainActor in
            monitor.handleReconfiguration(flags: CGDisplayChangeSummaryFlags(rawValue: raw))
        }
    }

    private func handleReconfiguration(flags: CGDisplayChangeSummaryFlags) {
        if activeApplyCount > 0 {
            Log.monitor.debug("reconfiguration ignored (own configuration change in progress)")
            return
        }
        // The pre-change heads-up carries no useful per-display detail.
        if flags == .beginConfigurationFlag {
            Log.monitor.debug("reconfiguration begin (ignored)")
            return
        }

        let quiet = max(1, settleSeconds)
        Log.monitor.debug("reconfiguration flags=\(flags.rawValue) → debounce \(quiet)s")
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(quiet))
            guard !Task.isCancelled else { return }
            Log.monitor.notice("displays settled (after \(quiet)s quiet)")
            self.onDisplaysSettled?()
        }
    }
}
