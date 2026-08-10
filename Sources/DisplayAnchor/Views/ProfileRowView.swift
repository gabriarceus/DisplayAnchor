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

            VStack(alignment: .leading, spacing: 1) {
                if isRenaming {
                    TextField(l("profile_name_placeholder"), text: $draftLabel)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .focused($renameFieldFocused)
                        .onSubmit(commitRename)
                        .onChange(of: renameFieldFocused) { _, focused in
                            if !focused { commitRename() }
                        }
                } else {
                    Text(profile.label)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .hoverTip(l("profile_rename_hint"))
                        .onTapGesture(count: 2, perform: startRenaming)
                }
                Text(l("profile_count_saved", countText, relativeDate(profile.savedAt)))
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
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .hoverTip(l("profile_confirm_delete_hint"))
                Button(action: cancelDeleteConfirmation) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .hoverTip(l("profile_keep_hint"))
            } else {
                Button(action: startDeleteConfirmation) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .hoverTip(l("profile_delete_hint"))
            }
        }
        .padding(.vertical, 2)
    }

    private var countText: String {
        let count = profile.displays.count
        return count == 1 ? l("display_count_one", count) : l("display_count_other", count)
    }

    private func startRenaming() {
        draftLabel = profile.label
        isRenaming = true
        renameFieldFocused = true
    }

    private func commitRename() {
        guard isRenaming else { return }
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

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
