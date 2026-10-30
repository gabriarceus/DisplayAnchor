import AppKit
import Sparkle

/// Uses a compact installation prompt and Sparkle's standard progress and error UI.
@MainActor
final class CompactUpdateUserDriver: NSObject, SPUUserDriver {
    private let config: AppConfig
    private let mayPresentUpdate: () -> Bool
    private let standard = SPUStandardUserDriver(hostBundle: .main, delegate: nil)
    private var pendingUpdate: SUAppcastItem?
    private var pendingState: SPUUserUpdateState?
    private var pendingReply: ((SPUUserUpdateChoice) -> Void)?
    private var alert: NSAlert?

    init(config: AppConfig, mayPresentUpdate: @escaping () -> Bool) {
        self.config = config
        self.mayPresentUpdate = mayPresentUpdate
    }

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

    func confirmationAlert(version: String, stage: SPUUserUpdateStage) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = config.l("updates_confirm_title", version)
        switch stage {
        case .notDownloaded, .downloaded:
            alert.informativeText = config.l("updates_confirm_message")
        case .installing:
            alert.informativeText = config.l("updates_confirm_restart")
        @unknown default:
            preconditionFailure("Unsupported update stage")
        }
        alert.addButton(withTitle: config.l("updates_confirm_install"))
        alert.addButton(withTitle: config.l("updates_confirm_cancel"))
        return alert
    }

    func showUpdateInFocus() {
        if let alert {
            alert.window.makeKeyAndOrderFront(nil)
            return
        }
        guard let item = pendingUpdate, let state = pendingState else {
            standard.showUpdateInFocus()
            return
        }
        if item.isInformationOnlyUpdate || item.isMajorUpgrade {
            guard let reply = pendingReply else { return }
            pendingReply = nil
            pendingUpdate = nil
            pendingState = nil
            standard.showUpdateFound(with: item, state: state, reply: reply)
            standard.showUpdateInFocus()
            return
        }
        let prompt = confirmationAlert(version: item.displayVersionString, stage: state.stage)
        alert = prompt
        NSApp.activate(ignoringOtherApps: true)
        let response = prompt.runModal()
        alert = nil
        let reply = pendingReply
        pendingReply = nil
        pendingUpdate = nil
        pendingState = nil
        reply?(response == .alertFirstButtonReturn ? .install : .dismiss)
    }

    func dismissUpdateInstallation() {
        pendingReply = nil
        pendingUpdate = nil
        pendingState = nil
        if let alert {
            NSApp.abortModal()
            alert.window.orderOut(nil)
            self.alert = nil
        }
        standard.dismissUpdateInstallation()
    }

    func dismissPendingUpdate() {
        guard let reply = pendingReply else { return }
        dismissUpdateInstallation()
        reply(.dismiss)
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

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void)
    {
        standard.showUpdateInstalledAndRelaunched(relaunched, acknowledgement: acknowledgement)
    }
}
