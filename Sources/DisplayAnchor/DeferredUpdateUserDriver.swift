import Sparkle

/// Sparkle user driver that holds offers from scheduled checks without showing
/// them, and shows an offer in Sparkle's standard update window when the user asks
/// for it. Progress, errors, and installation use the standard driver.
@MainActor
final class DeferredUpdateUserDriver: NSObject, SPUUserDriver {
    private let config: AppConfig
    private let mayPresentUpdate: () -> Bool
    private let standard = SPUStandardUserDriver(hostBundle: .main, delegate: nil)
    private var pendingUpdate: SUAppcastItem?
    private var pendingState: SPUUserUpdateState?
    /// Sparkle's reply for the current offer, held until it is answered once.
    private var pendingReply: ((SPUUserUpdateChoice) -> Void)?

    /// `mayPresentUpdate` returns false to dismiss offers that arrive while a
    /// channel change is waiting for a fresh check.
    init(config: AppConfig, mayPresentUpdate: @escaping () -> Bool) {
        self.config = config
        self.mayPresentUpdate = mayPresentUpdate
    }

    /// Holds the offer, or dismisses it when its channel is not selected. A
    /// user-initiated check shows it right away.
    func showUpdateFound(
        with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        guard mayPresentUpdate(), config.updateChannel.allows(appcastItem.channel) else {
            reply(.dismiss)
            return
        }
        standard.dismissUpdateInstallation()
        pendingUpdate = appcastItem
        pendingState = state
        pendingReply = reply
        if state.userInitiated { showUpdateInFocus() }
    }

    /// Shows the held offer in the standard update window, or brings the
    /// standard driver's current window to the front.
    func showUpdateInFocus() {
        guard let item = pendingUpdate, let state = pendingState else {
            standard.showUpdateInFocus()
            return
        }
        pendingUpdate = nil
        pendingState = nil
        standard.showUpdateFound(with: item, state: state) { [weak self] choice in
            self?.answer(choice)
        }
        standard.showUpdateInFocus()
    }

    func dismissUpdateInstallation() {
        pendingUpdate = nil
        pendingState = nil
        pendingReply = nil
        standard.dismissUpdateInstallation()
    }

    /// Dismisses the current offer, held or shown, and closes its window.
    func dismissPendingUpdate() {
        guard pendingReply != nil else { return }
        answer(.dismiss)
        dismissUpdateInstallation()
    }

    private func answer(_ choice: SPUUserUpdateChoice) {
        guard let reply = pendingReply else { return }
        pendingReply = nil
        reply(choice)
    }

    func show(
        _ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        standard.show(request, reply: reply)
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        standard.showUserInitiatedUpdateCheck(cancellation: cancellation)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        standard.showUpdateReleaseNotes(with: downloadData)
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {
        standard.showUpdateReleaseNotesFailedToDownloadWithError(error)
    }

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        standard.showUpdateNotFoundWithError(error, acknowledgement: acknowledgement)
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        standard.showUpdaterError(error, acknowledgement: acknowledgement)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        standard.showDownloadInitiated(cancellation: cancellation)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        standard.showDownloadDidReceiveExpectedContentLength(expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        standard.showDownloadDidReceiveData(ofLength: length)
    }

    func showDownloadDidStartExtractingUpdate() {
        standard.showDownloadDidStartExtractingUpdate()
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        standard.showExtractionReceivedProgress(progress)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        standard.showReady(toInstallAndRelaunch: reply)
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        standard.showInstallingUpdate(
            withApplicationTerminated: applicationTerminated,
            retryTerminatingApplication: retryTerminatingApplication)
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        standard.showUpdateInstalledAndRelaunched(relaunched, acknowledgement: acknowledgement)
    }
}
