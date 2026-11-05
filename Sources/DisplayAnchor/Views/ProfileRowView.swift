import AppKit
import MenuBarKit
import SwiftUI

/// One saved-layout row: label, display count, relative save time, with inline
/// rename, delete-with-confirmation, and (for the current set) a Restore button.
struct ProfileRowView: View {
    let profile: LayoutProfile
    let isCurrent: Bool
    let restoreDisabled: Bool
    let onRestore: () -> Void
    let onRename: (String) -> Void
    let onDelete: () -> Void

    @Environment(\.localizer) private var l
    @Environment(\.locale) private var locale

    @State private var isRenaming = false
    @State private var draftLabel = ""
    @State private var confirmingDelete = false
    @State private var confirmDeleteTask: Task<Void, Never>?
    @FocusState private var renameFieldFocused: Bool
    @State private var outsideClickMonitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: DisplayCountIcon.image(displays: profile.displays))
                .renderingMode(.template)
                .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)

            VStack(alignment: .leading, spacing: 1) {
                if isRenaming {
                    TextField(l("profile_name_placeholder"), text: $draftLabel)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .focused($renameFieldFocused)
                        .onSubmit(commitRename)
                        .onExitCommand(perform: cancelRename)
                        .onChange(of: renameFieldFocused) { _, focused in
                            if !focused { commitRename() }
                        }
                } else {
                    Text(profile.label)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .panelHelp(l("profile_rename_hint"))
                        .onTapGesture(count: 2, perform: startRenaming)
                }
                Text(
                    l(
                        "profile_count_saved", l.displayCount(profile.displays.count),
                        profile.savedAt.relativeText(locale: locale))
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            if isCurrent {
                Button(l("profile_restore"), action: onRestore)
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .disabled(restoreDisabled)
            }

            if confirmingDelete {
                Text(l("profile_delete_confirm"))
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                Button(action: confirmDelete) {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundStyle(.red)
                .accessibilityLabel(l("profile_confirm_delete_hint"))
                .panelHelp(l("profile_confirm_delete_hint"))
                Button(action: cancelDeleteConfirmation) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(l("profile_keep_hint"))
                .panelHelp(l("profile_keep_hint"))
            } else {
                Button(action: startDeleteConfirmation) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(l("profile_delete_hint"))
                .panelHelp(l("profile_delete_hint"))
            }
        }
        .padding(.vertical, 2)
        .onDisappear(perform: stopOutsideClickMonitor)
    }

    private func startRenaming() {
        draftLabel = profile.label
        isRenaming = true
        renameFieldFocused = true
        // The panel stays key and clicks on plain SwiftUI content take no focus, so
        // the field would keep editing until Return or Escape without this monitor.
        outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            let hit = event.window?.contentView?.hitTest(event.locationInWindow)
            if !(hit is NSText || hit is NSTextField) {
                MainActor.assumeIsolated { commitRename() }
            }
            return event
        }
    }

    private func stopOutsideClickMonitor() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    private func cancelRename() {
        stopOutsideClickMonitor()
        isRenaming = false
    }

    private func commitRename() {
        guard isRenaming else { return }
        stopOutsideClickMonitor()
        isRenaming = false
        let trimmed = draftLabel.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, trimmed != profile.label { onRename(trimmed) }
    }

    /// Reveals the inline confirm and auto-reverts after a few seconds, so a stray
    /// trash click clears itself without deleting anything.
    private func startDeleteConfirmation() {
        withAnimation { confirmingDelete = true }
        confirmDeleteTask?.cancel()
        confirmDeleteTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { withAnimation { confirmingDelete = false } }
        }
    }

    private func cancelDeleteConfirmation() {
        confirmDeleteTask?.cancel()
        withAnimation { confirmingDelete = false }
    }

    private func confirmDelete() {
        confirmDeleteTask?.cancel()
        confirmingDelete = false
        onDelete()
    }

}
