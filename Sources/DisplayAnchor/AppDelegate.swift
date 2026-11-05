import AppKit
import Combine
import MenuBarKit
import SwiftUI

/// AppKit shell: owns the status item and the panel that hosts all UI.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let config = AppConfig()
    private lazy var updates = UpdateController(config: config)
    private var store: LayoutStore?
    private var statusItem: NSStatusItem?
    private var statusItemController: StatusItemController?
    private var panel: MenuBarPanel?
    private let panelPresented = CurrentValueSubject<Bool, Never>(false)
    private let navigation = PanelNavigation<PanelScreen>(initial: .main)
    private var appearanceObserver: AnyCancellable?
    private var updateObserver: AnyCancellable?
    private var presentationObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()

        let store = LayoutStore(config: config)
        self.store = store

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem

        let panel = MenuBarPanel(
            rootView: PanelRootView(
                store: store,
                config: config,
                navigation: navigation,
                updates: updates,
                isPresented: panelPresented.eraseToAnyPublisher()
            ),
            width: PopoverView.popoverWidth
        )
        panel.onDismiss = { [weak self] in
            self?.navigation.screen = .main
        }
        self.panel = panel

        let controller = StatusItemController(statusItem: statusItem, panel: panel)
        statusItemController = controller
        presentationObserver = controller.$isPresented
            .removeDuplicates()
            .sink { [weak self] presented in
                if presented { self?.store?.refreshCurrentState() }
                self?.panelPresented.send(presented)
            }

        store.onStateChange = { [weak self] in
            self?.renderStatusItem()
        }
        // @Published emits on willSet, so hop to the next runloop tick to read the new value.
        appearanceObserver = config.$appAppearanceRaw
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyPanelAppearance() }
        updateObserver = updates.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] (_: UpdateController.Status) in
                self?.renderStatusItem()
                self?.announceAvailableUpdate()
            }
        applyPanelAppearance()
        store.start()
        renderStatusItem()
        updates.start()
    }

    /// Notifies the user about a pending update, once per version. The panel is
    /// the only place the update is otherwise visible, and it is closed most of
    /// the time, so a background find would go unnoticed.
    private func announceAvailableUpdate() {
        guard config.checkForUpdates, let version = updates.consumeUnannouncedUpdate() else { return }
        store?.notifier.send(
            title: config.l("notification_update_title"),
            body: config.l("notification_update_body", version)
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

        EditMenu.install(
            in: mainMenu, title: config.l("menu_edit"), undo: config.l("menu_undo"), redo: config.l("menu_redo"),
            cut: config.l("menu_cut"), copy: config.l("menu_copy"), paste: config.l("menu_paste"),
            selectAll: config.l("menu_select_all")
        )

        NSApp.mainMenu = mainMenu
    }

    /// Status item icon. The image is always a template (the system colors it for
    /// the menu bar), and state is conveyed by the symbol shape rather than a tint —
    /// a tinted/non-template image can render invisible after a display
    /// reconfiguration. An explicit symbol configuration keeps it crisp across
    /// displays with different backing scales. A pending update adds a dot in the
    /// corner.
    private func renderStatusItem() {
        guard let statusItemController, let store else { return }

        let image: NSImage?
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        if store.justRestored {
            image = NSImage(systemSymbolName: "checkmark.rectangle", accessibilityDescription: "DisplayAnchor")?
                .withSymbolConfiguration(configuration)
        } else if store.matchState == .differs {
            image = NSImage(
                systemSymbolName: "display.trianglebadge.exclamationmark", accessibilityDescription: "DisplayAnchor")?
                .withSymbolConfiguration(configuration)
        } else {
            // Steady state: rectangles mirroring the connected displays (main filled).
            image = DisplayCountIcon.image(displays: store.currentDisplays)
        }

        // A failed symbol lookup must never leave the menu bar blank.
        statusItemController.update(
            icon: image ?? DisplayCountIcon.image(displays: store.currentDisplays),
            hasBadge: updates.availableVersion != nil,
            accessibilityLabel: "DisplayAnchor"
        )
    }
}
