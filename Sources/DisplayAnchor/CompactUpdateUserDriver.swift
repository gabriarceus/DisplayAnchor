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

    func confirmationAlert(version: String, stage: SPUUserUpdateStage, releaseNotes: String? = nil)
        -> NSAlert
    {
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
        if let notes = releaseNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty
        {
            alert.accessoryView = releaseNotesView(notes)
        }
        return alert
    }

    private func releaseNotesView(_ notes: String) -> NSView {
        let width: CGFloat = 340
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 0))
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.textContainer?.containerSize = NSSize(
            width: width - 16, height: .greatestFiniteMagnitude)
        textView.string = notes
        if let container = textView.textContainer, let layout = textView.layoutManager {
            layout.ensureLayout(for: container)
            textView.setFrameSize(
                NSSize(width: width, height: ceil(layout.usedRect(for: container).height) + 16))
        }

        let scrollView = NSScrollView(
            frame: NSRect(x: 0, y: 0, width: width, height: min(180, textView.frame.height)))
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        let title = NSTextField(labelWithString: config.l("updates_whats_new"))
        title.font = .boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        let stack = NSStackView(views: [title, scrollView])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.frame = NSRect(
            x: 0, y: 0, width: width,
            height: title.intrinsicContentSize.height + 8 + scrollView.frame.height)
        NSLayoutConstraint.activate([
            scrollView.widthAnchor.constraint(equalToConstant: width),
            scrollView.heightAnchor.constraint(equalToConstant: scrollView.frame.height),
        ])
        return stack
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
        let prompt = confirmationAlert(
            version: item.displayVersionString, stage: state.stage,
            releaseNotes: item.itemDescriptionFormat == "plain-text" ? item.itemDescription : nil)
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
