import AppKit
import Combine
import MenuBarKit
import SwiftUI

/// AppKit shell: owns the status item and the panel that hosts all UI.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let config = AppConfig()
    private lazy var updateChecker = UpdateChecker(config: config)
    private var store: LayoutStore?
    private var statusItem: NSStatusItem?
    private var panel: MenuBarPanel?
    private var lastPanelDismiss: Date?
    private let navigation = PanelNavigation<PanelScreen>(initial: .main)
    private var appearanceObserver: AnyCancellable?
    private var updateObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()

        let store = LayoutStore(config: config)
        self.store = store

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        self.statusItem = statusItem

        let panel = MenuBarPanel(
            rootView: PanelRootView(
                store: store,
                config: config,
                navigation: navigation,
                updateChecker: updateChecker
            ),
            width: PopoverView.popoverWidth
        )
        panel.onDismiss = { [weak self] in
            guard let self else { return }
            // Leaving settings via an outside click still applies the settle interval.
            if self.navigation.screen == .settings { self.store?.applySettings() }
            self.navigation.screen = .main
            self.lastPanelDismiss = Date()
        }
        self.panel = panel

        store.onStateChange = { [weak self] in
            self?.renderStatusItem()
        }
        // @Published emits on willSet, so hop to the next runloop tick to read the new value.
        appearanceObserver = config.$appAppearanceRaw
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyPanelAppearance() }
        updateObserver = updateChecker.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.renderStatusItem()
                self?.announceAvailableUpdate()
            }
        applyPanelAppearance()
        store.start()
        renderStatusItem()
        updateChecker.start()
    }

    /// Notifies the user about a pending update, once per version. The panel is
    /// the only place the update is otherwise visible, and it is closed most of
    /// the time, so a background find would go unnoticed.
    private func announceAvailableUpdate() {
        guard config.checkForUpdates, let update = updateChecker.consumeUnannouncedUpdate() else { return }
        store?.notifier.send(
            title: config.l("notification_update_title"),
            body: config.l("notification_update_body", update.version)
        )
    }

    /// Forces the panel's appearance for the dark/light settings; system follows
    /// the system appearance. The glass tint is applied separately by the chrome.
    private func applyPanelAppearance() {
        switch config.appAppearance {
        case .system:
            panel?.appearance = nil
        case .dark:
            panel?.appearance = NSAppearance(named: .darkAqua)
        case .light:
            panel?.appearance = NSAppearance(named: .aqua)
        }
    }

    /// Accessory apps have no visible menu bar, but keyboard shortcuts (Cmd+C/V/X/A,
    /// undo/redo) only resolve through the main menu — without this, paste does not
    /// work in the settings text fields.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Quit DisplayAnchor",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func togglePopover() {
        guard let panel else { return }
        if panel.isVisible {
            panel.dismiss()
            return
        }
        // A click on the status item that just dismissed the panel (outside-click
        // monitor) must not be interpreted as a request to reopen it.
        if let last = lastPanelDismiss, Date().timeIntervalSince(last) < 0.2 { return }

        store?.refreshCurrentState()
        // Opening the panel is the moment the update state is read, so re-check
        // here too; the daily gate makes this a no-op on all but the first open
        // of the day.
        updateChecker.checkIfDue()
        // Present on the next runloop tick: the status-bar button runs a mouse
        // tracking loop on click, and presenting mid-tracking prevents the panel
        // from appearing.
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, !panel.isVisible else { return }
            panel.present(at: self.panelTopLeft())
        }
    }

    /// Top-left corner (screen coordinates) for presenting the panel: just below
    /// the status item when it is on-screen, otherwise under the menu bar at the
    /// top-right of the main screen — a sane fallback when a menu bar manager has
    /// moved the icon off-screen.
    private func panelTopLeft() -> NSPoint {
        let width = PopoverView.popoverWidth
        let gap: CGFloat = 6

        if let button = statusItem?.button,
           let window = button.window,
           let screen = window.screen ?? NSScreen.main {
            let buttonOnScreen = window.convertToScreen(button.convert(button.bounds, to: nil))
            if screen.frame.intersects(buttonOnScreen) {
                let visible = screen.visibleFrame
                let x = min(max(buttonOnScreen.midX - width / 2, visible.minX + 8), visible.maxX - width - 8)
                return NSPoint(x: x, y: buttonOnScreen.minY - gap)
            }
        }

        Log.ui.debug("Status item off-screen; presenting panel at default top-right position")
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        return NSPoint(x: visible.maxX - width - 8, y: visible.maxY - 8)
    }

    /// Status item icon. The image is always a template (the system colors it for
    /// the menu bar), and state is conveyed by the symbol shape rather than a tint —
    /// a tinted/non-template image can render invisible after a display
    /// reconfiguration. An explicit symbol configuration keeps it crisp across
    /// displays with different backing scales. A pending update adds a dot in the
    /// corner, for the same reason drawn in the template's own color.
    private func renderStatusItem() {
        guard let button = statusItem?.button, let store else { return }

        let image: NSImage?
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        if store.justRestored {
            image = NSImage(systemSymbolName: "checkmark.rectangle", accessibilityDescription: "DisplayAnchor")?
                .withSymbolConfiguration(configuration)
        } else if store.matchState == .differs {
            image = NSImage(systemSymbolName: "display.trianglebadge.exclamationmark", accessibilityDescription: "DisplayAnchor")?
                .withSymbolConfiguration(configuration)
        } else {
            // Steady state: rectangles mirroring the connected displays (main filled).
            image = DisplayCountIcon.image(displays: store.currentDisplays)
        }

        // A failed symbol lookup must never leave the menu bar blank.
        var resolved = image ?? DisplayCountIcon.image(displays: store.currentDisplays)
        if updateChecker.availableUpdate != nil {
            resolved = resolved.withNotificationDot()
        }
        resolved.isTemplate = true
        button.image = resolved
        button.contentTintColor = nil
        button.imagePosition = .imageOnly
    }
}

private extension NSImage {
    /// Copy of the image with a small filled dot in the top-trailing corner, as a
    /// template so the menu bar tints dot and icon alike. The canvas grows to the
    /// right to fit the dot instead of drawing it over the icon.
    func withNotificationDot(diameter: CGFloat = 4, gap: CGFloat = 1.5) -> NSImage {
        let canvas = NSSize(width: size.width + gap + diameter, height: size.height)
        let badged = NSImage(size: canvas, flipped: false) { _ in
            self.draw(in: NSRect(origin: .zero, size: self.size))
            let dot = NSRect(
                x: canvas.width - diameter,
                y: canvas.height - diameter,
                width: diameter,
                height: diameter
            )
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        badged.isTemplate = true
        return badged
    }
}
