import MenuBarKit
import SwiftUI

/// Display details bar: a disclosure toggle for the details list and a Copy all
/// action with a short confirmation.
struct DisplayDetailHeader: View {
    @Binding var expanded: Bool
    let onCopyAll: () -> Void

    @Environment(\.localizer) private var l

    @State private var justCopied = false
    @State private var copiedTask: Task<Void, Never>?

    var body: some View {
        HStack {
            Button {
                expanded.toggle()
            } label: {
                // One rotated chevron: chevron.down and chevron.right differ in width and shift the title.
                Label {
                    Text(l("display_details"))
                } icon: {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            if justCopied {
                Label(l("display_copied"), systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .lineLimit(1)
                    .transition(.opacity)
            }

            Button {
                onCopyAll()
                justCopied = true  // appears immediately
                copiedTask?.cancel()
                copiedTask = Task {
                    try? await Task.sleep(for: .seconds(1))
                    if !Task.isCancelled { withAnimation(.easeOut(duration: 0.15)) { justCopied = false } }
                }
            } label: {
                Label(l("display_copy_all"), systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .panelHelp(l("display_copy_hint"))
        }
    }
}

/// Per-display diagnostic list: raw identity (model, serial, vendor, unit, UUID)
/// plus an explicit warning when two displays are indistinguishable (same EDID),
/// so a restore mismatch can be attributed to that vs. a bug.
struct DisplayDetailView: View {
    let displays: [DisplaySnapshot]
    let ambiguousKeys: Set<String>
    let onCopyDisplay: (DisplaySnapshot) -> Void

    @Environment(\.localizer) private var l

    /// `snapshotKey` of the display whose diagnostics were just copied.
    @State private var copiedKey: String?
    @State private var copiedTask: Task<Void, Never>?
    @State private var hoveredKey: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(displays, id: \.stableID.snapshotKey) { display in
                detailRow(display)
            }
        }
    }

    private func copy(_ display: DisplaySnapshot) {
        onCopyDisplay(display)
        copiedKey = display.stableID.snapshotKey  // appears immediately
        copiedTask?.cancel()
        copiedTask = Task {
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { withAnimation(.easeOut(duration: 0.15)) { copiedKey = nil } }
        }
    }

    /// Copy button for one display, visible while the pointer is over its row. Its space is
    /// always reserved, so showing it or its confirmation never moves the row.
    private func rowCopyButton(_ display: DisplaySnapshot) -> some View {
        let key = display.stableID.snapshotKey
        let copied = copiedKey == key
        let visible = hoveredKey == key && !copied
        return ZStack(alignment: .trailing) {
            Label(l("display_copied"), systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
                .lineLimit(1)
                .opacity(copied ? 1 : 0)
            Button {
                copy(display)
            } label: {
                Label(l("display_copy"), systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .panelHelp(l("display_copy_one_hint"))
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
        }
    }

    private func detailRow(_ display: DisplaySnapshot) -> some View {
        let isAmbiguous = ambiguousKeys.contains(display.stableID.identityKey)
        let id = display.stableID
        let mode = display.mode
        let refresh = mode.refresh > 0 ? " · \(Int(mode.refresh.rounded())) Hz" : ""
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(display.name).font(.caption).bold()
                if display.isMain { tag(l("display_main").uppercased(), .accentColor) }
                if isAmbiguous { tag(l("display_indistinguishable"), .orange) }
                Spacer()
                rowCopyButton(display)
            }
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
                field(l("display_field_position"), "\(display.originX), \(display.originY)")
                field(l("display_field_mode"), "\(mode.width)×\(mode.height) pt\(refresh)")
                field(
                    l("display_field_pixels"), "\(mode.pixelWidth)×\(mode.pixelHeight)\(mode.isHiDPI ? " · HiDPI" : "")"
                )
                // Identifiers are passed as strings so they are not grouped like quantities.
                field(
                    l("display_field_hardware"),
                    l("display_hardware_value", String(id.vendor), String(id.model), String(id.unitNumber)))
                field(l("display_field_serial"), id.serialText)
                GridRow {
                    label("UUID")
                    Text(id.uuid ?? "—")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isAmbiguous ? Color.orange.opacity(0.08) : Color.secondary.opacity(0.06))
        )
        .onHover { hovering in
            let key = display.stableID.snapshotKey
            if hovering {
                hoveredKey = key
            } else if hoveredKey == key {
                hoveredKey = nil
            }
        }
    }

    private func field(_ name: String, _ value: String) -> some View {
        GridRow {
            label(name)
            Text(value)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.2)))
            .foregroundStyle(color)
    }
}
