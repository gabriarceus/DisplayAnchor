import AppKit
import MenuBarKit
import SwiftUI

/// Root popover: current arrangement (mini-map + diagnostics), save/restore
/// actions for the current display set, and the list of saved layouts.
struct PopoverView: View {
    static let popoverWidth: CGFloat = Theme.defaultPanelWidth
    static let popoverHeight: CGFloat = 540

    @ObservedObject var store: LayoutStore
    /// Version of a pending update, surfaced as a badge on the settings button —
    /// a background check the user never sees would be pointless.
    let availableUpdateVersion: String?
    let onOpenSettings: () -> Void
    let onEditLayout: () -> Void

    @Environment(\.localizer) private var l

    @State private var showSavedConfirmation = false
    @State private var confirmationTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()

            // Fixed (non-scrolling) current-arrangement section. Keeping the mini-map
            // out of the ScrollView means it never moves when the details/list below
            // scroll, and it can't be stretched past the popover edge.
            if store.currentDisplays.isEmpty {
                Text(l("popover_no_displays"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    DisplayMapView(
                        displays: store.currentDisplays,
                        onSetMain: { store.setMainDisplay($0) },
                        onRotate: { store.rotateDisplay($0, to: $1) },
                        onEdit: store.currentDisplays.count >= 2 ? onEditLayout : nil
                    )
                    .frame(height: 120)
                    statusLine
                    actionButtons
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }

            Divider()

            // Scrolling section: per-display details (expandable) and saved layouts.
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !store.currentDisplays.isEmpty {
                        DisplayDetailView(
                            displays: store.currentDisplays,
                            ambiguousKeys: store.ambiguousIdentityKeys,
                            onCopyDiagnostics: copyDiagnostics
                        )
                        Divider()
                    }
                    savedProfilesSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }

            Divider()

            footer
                .padding(12)
        }
        .frame(width: Self.popoverWidth, height: Self.popoverHeight)
    }

    private var header: some View {
        PanelHeader(title: "Display Layout", leading: {
            Image(nsImage: DisplayCountIcon.image(displays: store.currentDisplays))
                .renderingMode(.template)
        })
    }

    private var statusLine: some View {
        HStack(spacing: 5) {
            Image(systemName: statusIcon).foregroundStyle(statusColor)
            Text(statusText).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if store.currentDisplays.count >= 2 {
                Button(action: onEditLayout) {
                    Image(systemName: "rectangle.3.group")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .hoverTip(l("popover_edit_layout_hint"))
            }
        }
    }

    /// Save/Update and pause/resume auto-restore share a row. The pause control is
    /// shown only while automatic restore is enabled.
    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button(saveButtonTitle, action: saveCurrentLayout)
                .buttonStyle(.borderedProminent)
                .lineLimit(1)
                .disabled(store.matchState == .matches)

            snoozeControl

            Spacer(minLength: 0)

            if showSavedConfirmation {
                Label(l("popover_saved_confirmation"), systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .lineLimit(1)
            } else if store.config.autoRestoreEnabled,
                      store.isAutoRestoreSnoozed,
                      let until = store.autoRestoreSnoozedUntil {
                Text(l("popover_paused_until", timeString(until)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var snoozeControl: some View {
        if store.config.autoRestoreEnabled {
            if store.isAutoRestoreSnoozed, let until = store.autoRestoreSnoozedUntil {
                Button {
                    store.resumeAutoRestore()
                } label: {
                    Label(l("popover_resume"), systemImage: "play.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .hoverTip(l("popover_resume_hint", minutesRemaining(until: until)))
            } else {
                Button {
                    store.snoozeAutoRestore(for: 15 * 60)
                } label: {
                    Label(l("popover_pause_15"), systemImage: "pause.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .hoverTip(l("popover_pause_hint"))
            }
        }
    }

    private func minutesRemaining(until date: Date) -> Int {
        max(0, Int((date.timeIntervalSinceNow / 60).rounded(.up)))
    }

    private var savedProfilesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l("popover_saved_layouts"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if store.savedProfiles.isEmpty {
                Text(l("popover_empty_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.savedProfiles, id: \.fingerprint) { profile in
                    ProfileRowView(
                        profile: profile,
                        isCurrent: profile.fingerprint == store.currentFingerprint,
                        restoreDisabled: store.matchState == .matches,
                        onRestore: { store.restoreNow() },
                        onRename: { store.rename(fingerprint: profile.fingerprint, to: $0) },
                        onDelete: { store.deleteProfile(fingerprint: profile.fingerprint) }
                    )
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if let date = store.lastRestoreAt {
                Text(l("popover_last_restore", relativeTime(date)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            GlassIconButton(systemImage: "gearshape") {
                onOpenSettings()
            }
            .overlay(alignment: .topTrailing) {
                if availableUpdateVersion != nil {
                    Circle()
                        .fill(.orange)
                        .frame(width: 7, height: 7)
                        .offset(x: 1, y: -1)
                }
            }
            .hoverTip(
                availableUpdateVersion.map { l("updates_available", $0) } ?? l("common_settings")
            )

            GlassIconButton(systemImage: "power") {
                NSApp.terminate(nil)
            }
            .hoverTip(l("common_quit"))
        }
    }

    // MARK: - Derived presentation

    private var saveButtonTitle: String {
        store.matchedProfile != nil ? l("popover_update_layout") : l("popover_save_layout")
    }

    private var statusText: String {
        switch store.matchState {
        case .noDisplays: return l("popover_status_no_displays")
        case .noSavedLayout: return l("popover_status_no_saved")
        case .matches: return l("popover_status_matches", store.matchedProfile?.label ?? "")
        case .differs: return l("popover_status_differs", store.matchedProfile?.label ?? "")
        }
    }

    private var statusIcon: String {
        switch store.matchState {
        case .matches: return "checkmark.circle"
        case .differs: return "exclamationmark.triangle"
        case .noSavedLayout, .noDisplays: return "info.circle"
        }
    }

    private var statusColor: Color {
        switch store.matchState {
        case .matches: return .green
        case .differs: return .orange
        case .noSavedLayout, .noDisplays: return .secondary
        }
    }

    // MARK: - Actions

    private func saveCurrentLayout() {
        store.saveCurrentLayout(label: store.matchedProfile?.label ?? "")
        showSavedConfirmation = true
        confirmationTask?.cancel()
        confirmationTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled { showSavedConfirmation = false }
        }
    }

    private func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(store.diagnosticsText(), forType: .string)
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
