import MenuBarKit
import SwiftUI

/// Screen currently shown inside the panel.
enum PanelScreen {
    case main
    case settings
    case editLayout
}

/// Root content of the panel: swaps between the main view and settings in place,
/// so everything lives in a single panel instead of a separate window. Chrome is
/// provided by [PanelChrome] since the hosting window is borderless and transparent.
struct PanelRootView: View {
    @ObservedObject var store: LayoutStore
    @ObservedObject var config: AppConfig
    @ObservedObject var navigation: PanelNavigation<PanelScreen>
    @ObservedObject var updateChecker: UpdateChecker
    @StateObject private var systemAccent = SystemAccentObserver()

    var body: some View {
        PanelChrome(tint: glassTint) {
            content.hoverTipHost().environment(\.localizer, config.localizer)
        }
    }

    private var glassTint: Color? {
        switch config.appTintMode {
        case .none: nil
        case .system: systemAccent.color.opacity(0.3)
        case .custom: config.appTint.glassTint
        }
    }

    @ViewBuilder
    private var content: some View {
        switch navigation.screen {
        case .main:
            PopoverView(
                store: store,
                availableUpdateVersion: updateChecker.availableUpdate?.version,
                onOpenSettings: { navigation.screen = .settings },
                onEditLayout: { navigation.screen = .editLayout }
            )
        case .settings:
            SettingsView(config: store.config, notifier: store.notifier, updates: updateChecker) {
                store.applySettings()
                navigation.screen = .main
            }
        case .editLayout:
            LayoutEditorView(store: store) {
                navigation.screen = .main
            }
        }
    }
}

extension AppTint {
    /// Base hue of the tint.
    var baseColor: Color {
        switch self {
        case .blue: Color(red: 0.36, green: 0.56, blue: 0.90)
        case .purple: Color(red: 0.62, green: 0.47, blue: 0.87)
        case .pink: Color(red: 0.90, green: 0.49, blue: 0.68)
        case .red: Color(red: 0.87, green: 0.40, blue: 0.38)
        case .orange: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .yellow: Color(red: 0.88, green: 0.72, blue: 0.32)
        case .green: Color(red: 0.44, green: 0.74, blue: 0.44)
        case .graphite: Color(red: 0.55, green: 0.57, blue: 0.60)
        case .teal: Color(red: 0.30, green: 0.72, blue: 0.72)
        }
    }

    /// Subtle wash over the glass; opacity keeps it translucent.
    var glassTint: Color { baseColor.opacity(0.3) }
}
