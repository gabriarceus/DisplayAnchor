import MenuBarKit
import SwiftUI

/// Collapsible per-display diagnostic list: raw identity (model, serial, vendor,
/// unit, UUID) plus an explicit warning when two displays are indistinguishable
/// (same EDID), so a restore mismatch can be attributed to that vs. a bug.
struct DisplayDetailView: View {
    let displays: [DisplaySnapshot]
    let ambiguousKeys: Set<String>
    let onCopyDiagnostics: () -> Void

    @Environment(\.localizer) private var l

    @State private var expanded = false
    @State private var justCopied = false
    @State private var copiedTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    expanded.toggle()
                } label: {
                    Label(l("display_details"), systemImage: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                if justCopied {
                    Label(l("display_copied"), systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .lineLimit(1)
                        .transition(.opacity)
                }

                Button(action: copy) {
                    Label(l("display_copy"), systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .hoverTip(l("display_copy_hint"))
            }

            if expanded {
                ForEach(Array(displays.enumerated()), id: \.offset) { _, display in
                    detailRow(display)
                }
            }
        }
    }

    private func copy() {
        onCopyDiagnostics()
        justCopied = true // appears immediately
        copiedTask?.cancel()
        copiedTask = Task {
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { withAnimation(.easeOut(duration: 0.15)) { justCopied = false } }
        }
    }

    private func detailRow(_ display: DisplaySnapshot) -> some View {
        let isAmbiguous = ambiguousKeys.contains(display.stableID.identityKey)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(display.name).font(.caption).bold()
                if display.isMain { tag("MAIN", .accentColor) }
                if isAmbiguous { tag("⚠︎ indistinguishable", .orange) }
            }
            Text(geometryLine(display))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("model \(display.stableID.model) · serial \(display.stableID.serial) · vendor \(display.stableID.vendor) · unit \(display.stableID.unitNumber)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("uuid \(display.stableID.uuid ?? "—")")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isAmbiguous ? Color.orange.opacity(0.08) : Color.secondary.opacity(0.06))
        )
    }

    private func geometryLine(_ display: DisplaySnapshot) -> String {
        let hz = display.mode.refresh > 0 ? "\(Int(display.mode.refresh.rounded()))Hz" : "—"
        let hiDPI = display.mode.isHiDPI ? " · HiDPI" : ""
        return "pos (\(display.originX), \(display.originY)) · \(display.mode.width)×\(display.mode.height) pt · \(display.mode.pixelWidth)×\(display.mode.pixelHeight) px\(hiDPI) · \(hz)"
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
