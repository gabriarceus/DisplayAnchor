import MenuBarKit
import SwiftUI

/// One saved-layout row: label, display count, relative save time, with inline
/// rename, delete-with-confirmation, and (for the current set) a Restore button.
/// While delete waits for confirmation, the row shows only the label and the confirm controls at the same height.
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

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: DisplayCountIcon.image(displays: profile.displays))
                .renderingMode(.template)
                .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)

            // Both lines stay in the layout and are only hidden, so renaming and the
            // delete confirmation keep the row height; the rename field covers both lines.
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.label)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .panelHelp(l("profile_rename_hint"))
                    .onTapGesture(count: 2, perform: startRenaming)
                    .opacity(isRenaming ? 0 : 1)
                Text(
                    l(
                        "profile_count_saved", l.displayCount(profile.displays.count),
                        profile.savedAt.relativeText(locale: locale))
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .opacity(confirmingDelete || isRenaming ? 0 : 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                if isRenaming {
                    TextField(l("profile_name_placeholder"), text: $draftLabel)
                        .font(.subheadline)
                        .inputChrome(focused: renameFieldFocused)
                        .focused($renameFieldFocused)
                        .onSubmit(commitRename)
                        .onExitCommand(perform: cancelRename)
                        .onChange(of: renameFieldFocused) { _, focused in
                            if !focused { commitRename() }
                        }
                }
            }

            if isCurrent && !confirmingDelete {
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
        .onClickOutsideTextInput(isActive: isRenaming, perform: commitRename)
    }

    private func startRenaming() {
        draftLabel = profile.label
        isRenaming = true
        renameFieldFocused = true
    }

    private func cancelRename() {
        isRenaming = false
    }

    private func commitRename() {
        guard isRenaming else { return }
        isRenaming = false
        let trimmed = draftLabel.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, trimmed != profile.label { onRename(trimmed) }
    }

    /// Reveals the inline confirm, which hides the subtitle and Restore, and
    /// auto-reverts after 5 seconds without deleting anything. The swap is not
    /// animated: a fade would overlap the outgoing and incoming controls.
    private func startDeleteConfirmation() {
        confirmingDelete = true
        confirmDeleteTask?.cancel()
        confirmDeleteTask = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { confirmingDelete = false }
        }
    }

    private func cancelDeleteConfirmation() {
        confirmDeleteTask?.cancel()
        confirmingDelete = false
    }

    private func confirmDelete() {
        confirmDeleteTask?.cancel()
        confirmingDelete = false
        onDelete()
    }

}
