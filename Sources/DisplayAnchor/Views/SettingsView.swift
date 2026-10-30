import AppKit
import MenuBarKit
import ServiceManagement
import SwiftUI

/// Settings form. Toggles write through to UserDefaults immediately; the settle
/// interval is re-applied to the monitor when leaving the screen via [onBack].
/// The panel resizes to fit the whole form; scrolling (without indicators) kicks
/// in only when the content is taller than the screen.
struct SettingsView: View {
    @ObservedObject var config: AppConfig
    @ObservedObject var notifier: Notifier
    @ObservedObject var updates: UpdateController
    let onBack: () -> Void

    @Environment(\.localizer) private var l

    static let settleRange = 1...60

    @State private var launchAtLogin = false
    @State private var launchAtLoginHint: String?
    @State private var formHeight: CGFloat?
    @FocusState private var settleFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                form
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        formHeight = height
                    }
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(!needsScroll)
            .frame(height: formHeight.map { min($0, maxFormHeight) })
        }
        .frame(width: PopoverView.popoverWidth)
        .onAppear {
            launchAtLogin = LaunchAtLogin.isEnabled
        }
        .onChange(of: launchAtLogin) { _, enabled in
            applyLaunchAtLogin(enabled)
        }
        .onChange(of: config.notifyOnRestore) { _, enabled in
            if enabled { notifier.requestAuthorizationIfNeeded() }
        }
        .onChange(of: config.checkForUpdates) { _, enabled in
            updates.setAutomaticChecks(enabled)
        }
        .onChange(of: config.updateChannelRaw) { _, _ in
            updates.updateChannelChanged()
        }
        .onChange(of: config.settleSeconds) { _, value in
            // The text field accepts any number; clamp typed values to the range.
            let clamped = min(max(value, Self.settleRange.lowerBound), Self.settleRange.upperBound)
            if clamped != value { config.settleSeconds = clamped }
        }
    }

    /// Height available to the form below the header: the panel hangs from the
    /// menu bar, so the usable space is the screen's visible height minus the
    /// header and a bottom margin.
    private var maxFormHeight: CGFloat {
        let available = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.height ?? 700
        return available - 80
    }

    private var needsScroll: Bool {
        (formHeight ?? 0) > maxFormHeight
    }

    private var header: some View {
        PanelHeader(
            title: l("common_settings"),
            leading: {
                GlassIconButton(systemImage: "chevron.left", action: onBack)
                    .hoverTip(l("common_back"))
            }
        )
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, 10)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            section(l("settings_section_restore")) { restoreSection }
            section(l("common_appearance")) { appearanceSection }
            section(l("settings_section_notifications")) { notificationsSection }
            section(l("settings_section_advanced")) { advancedSection }
            section(l("settings_section_general")) { generalSection }
            section(l("settings_section_updates")) { updatesSection }
            footer
        }
        .padding(Theme.Spacing.m)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionLabel(title)
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                content()
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private var restoreSection: some View {
        toggleRow(l("settings_auto_restore_toggle"), isOn: $config.autoRestoreEnabled)
        Text(l("settings_auto_restore_description"))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var appearanceSection: some View {
        HStack {
            Text(l("common_appearance"))
            Spacer()
            Picker(l("common_appearance"), selection: $config.appAppearanceRaw) {
                Text(l("common_system")).tag(AppAppearance.system.rawValue)
                Text(l("common_dark")).tag(AppAppearance.dark.rawValue)
                Text(l("common_light")).tag(AppAppearance.light.rawValue)
            }
            .labelsHidden()
            .fixedSize()
        }
        HStack {
            Text(l("common_tint"))
            Spacer()
            Picker(l("common_tint"), selection: $config.appTintModeRaw) {
                Text(l("common_none")).tag(AppTintMode.none.rawValue)
                Text(l("common_match_macos")).tag(AppTintMode.system.rawValue)
                Text(l("common_custom")).tag(AppTintMode.custom.rawValue)
            }
            .labelsHidden()
            .fixedSize()
        }
        HStack {
            Text(l("common_language"))
            Spacer()
            Picker(l("common_language"), selection: $config.appLanguageRaw) {
                ForEach(
                    Bundle.appResources.languageOptions(systemLabel: l("common_language_system"))
                ) { option in
                    Text(option.name).tag(option.code)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
        if config.appTintMode == .custom {
            HStack(spacing: Theme.Spacing.s) {
                Spacer()
                ForEach(AppTint.allCases, id: \.rawValue) { tint in
                    tintSwatch(tint)
                }
            }
        }
    }

    private func tintSwatch(_ tint: AppTint) -> some View {
        Button {
            config.appTintRaw = tint.rawValue
        } label: {
            Circle()
                .fill(tint.baseColor)
                .frame(width: 16, height: 16)
                .overlay(
                    Circle()
                        .strokeBorder(
                            .primary.opacity(config.appTint == tint ? 0.6 : 0), lineWidth: 1.5
                        )
                        .padding(-3)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(tint.rawValue.capitalized)
    }

    @ViewBuilder
    private var notificationsSection: some View {
        toggleRow(l("settings_notify_toggle"), isOn: $config.notifyOnRestore)
        if notifier.authorizationDenied {
            Text(l("common_notifications_denied"))
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var advancedSection: some View {
        HStack {
            Text(l("settings_settle_label"))
            Spacer()
            TextField("", value: $config.settleSeconds, format: .number)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 50)
                .focused($settleFieldFocused)
                .inputChrome(focused: settleFieldFocused)
            Stepper("", value: $config.settleSeconds, in: Self.settleRange)
                .labelsHidden()
        }
        Text(
            l(
                "settings_settle_description", Self.settleRange.lowerBound,
                Self.settleRange.upperBound)
        )
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var generalSection: some View {
        toggleRow(l("settings_launch_at_login"), isOn: $launchAtLogin)
        if let hint = launchAtLoginHint {
            Text(hint)
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var updatesSection: some View {
        toggleRow(l("updates_auto_check"), isOn: $config.checkForUpdates)

        HStack {
            Text(l("updates_channel"))
            Spacer()
            Picker(l("updates_channel"), selection: $config.updateChannelRaw) {
                Text(l("updates_channel_stable")).tag(UpdateChannel.stable.rawValue)
                Text(l("updates_channel_rc")).tag(UpdateChannel.releaseCandidate.rawValue)
            }
            .labelsHidden()
            .fixedSize()
        }
        if config.updateChannel == .releaseCandidate {
            Text(l("updates_channel_rc_hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        HStack(spacing: Theme.Spacing.s) {
            Button(l("updates_check_now")) { updates.checkNow() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(updates.status == .checking)
            Spacer()
            updateStatusLabel
        }

        if let version = updates.availableVersion {
            Button(l("updates_install", version)) { updates.install() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Link(l("updates_release_notes"), destination: UpdateController.releasesURL)
                .font(.caption)
        }
    }

    /// Status note closing the form: the running version and a shortcut to the
    /// project page. Deliberately outside the sections, so it reads as a footnote
    /// rather than a setting.
    private var footer: some View {
        HStack {
            Text("\(l("updates_current_version")) \(updates.currentVersion)")
                .monospacedDigit()
            Spacer()
            Link(destination: UpdateController.repositoryURL) {
                HStack(spacing: 2) {
                    Text(UpdateController.repository)
                    Image(systemName: "arrow.up.right")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Theme.Spacing.xs)
    }

    @ViewBuilder
    private var updateStatusLabel: some View {
        switch updates.status {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .upToDate:
            Text(l("updates_up_to_date"))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .available(let version):
            Text(l("updates_available", version))
                .font(.caption)
                .foregroundStyle(.orange)
        case .failed:
            Text(l("updates_check_failed"))
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        guard LaunchAtLogin.isBundled else {
            if enabled {
                launchAtLoginHint = l("settings_launch_hint_unbundled")
                launchAtLogin = false
            }
            return
        }
        guard enabled != LaunchAtLogin.isEnabled else { return }
        do {
            try LaunchAtLogin.set(enabled)
            launchAtLoginHint =
                SMAppService.mainApp.status == .requiresApproval
                ? l("settings_launch_hint_approval")
                : nil
        } catch {
            launchAtLoginHint = error.localizedDescription
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }
}

private enum LaunchAtLogin {
    static var isBundled: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        guard isBundled else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
