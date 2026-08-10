import MenuBarKit
import SwiftUI

/// Proportional mini-map of the current display arrangement. Each display is drawn
/// as a rounded rect at its real relative position; the main display is highlighted.
/// The whole arrangement is always scaled to fit the available size (so even many
/// displays stay inside the popover), and labels degrade gracefully as rects shrink.
///
/// When the action closures are supplied, each display gains a right-click menu for
/// live quick actions (set main / rotate) and an entry into the layout editor.
struct DisplayMapView: View {
    let displays: [DisplaySnapshot]
    var onSetMain: ((DisplaySnapshot) -> Void)? = nil
    var onRotate: ((DisplaySnapshot, Int) -> Void)? = nil
    var onEdit: (() -> Void)? = nil

    @Environment(\.localizer) private var l

    private var hasMenu: Bool { onSetMain != nil || onRotate != nil || onEdit != nil }

    var body: some View {
        GeometryReader { geometry in
            let footprints = displays.map(footprint)
            let map = DisplayMapGeometry(footprints: footprints, in: geometry.size)
            ZStack(alignment: .topLeading) {
                ForEach(Array(displays.enumerated()), id: \.offset) { index, display in
                    let rect = map.rect(for: footprints[index])
                    displayRect(display, size: rect.size)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .clipped()
    }

    @ViewBuilder
    private func displayRect(_ display: DisplaySnapshot, size: CGSize) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4)
        shape
            .fill(display.isMain ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.12))
            .overlay(
                shape.strokeBorder(
                    display.isMain ? Color.accentColor : Color.secondary.opacity(0.5),
                    lineWidth: display.isMain ? 1.5 : 1
                )
            )
            .overlay(label(for: display, in: size))
            .overlay(alignment: .topTrailing) { rotationBadge(for: display, in: size) }
            .contentShape(shape)
            .optionalContextMenu(hasMenu) { menuContent(for: display) }
    }

    /// Corner badge showing the angle of a rotated display. The rect's shape
    /// already conveys 90°/270°; the badge makes it explicit and covers 180°.
    @ViewBuilder
    private func rotationBadge(for display: DisplaySnapshot, in size: CGSize) -> some View {
        let degrees = Int(display.rotation.rounded())
        if degrees != 0, min(size.width, size.height) >= 24 {
            Text("\(degrees)°")
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
                .padding(2)
                .hoverTip(l("display_rotated_hint", degrees))
        }
    }

    @ViewBuilder
    private func menuContent(for display: DisplaySnapshot) -> some View {
        if let onSetMain {
            Button(l("display_set_main")) { onSetMain(display) }
                .disabled(display.isMain)
        }
        if let onRotate {
            Menu(l("display_rotate")) {
                ForEach([0, 90, 180, 270], id: \.self) { degrees in
                    Button {
                        onRotate(display, degrees)
                    } label: {
                        if Int(display.rotation.rounded()) == degrees {
                            Label("\(degrees)°", systemImage: "checkmark")
                        } else {
                            Text("\(degrees)°")
                        }
                    }
                }
            }
        }
        if let onEdit {
            if onSetMain != nil || onRotate != nil { Divider() }
            Button(l("display_edit_layout")) { onEdit() }
        }
    }

    /// Effective footprint. Mode dimensions already follow the display's
    /// orientation (a 90°/270° display reports swapped width/height), so they map
    /// to the on-screen rect as-is.
    private func footprint(_ display: DisplaySnapshot) -> CGRect {
        CGRect(
            x: CGFloat(display.originX),
            y: CGFloat(display.originY),
            width: CGFloat(max(display.mode.width, 1)),
            height: CGFloat(max(display.mode.height, 1))
        )
    }

    /// Label detail scales with the rect: full info on roomy rects, just the name on
    /// medium ones, nothing on tiny ones (e.g. a 10-monitor wall). Thresholds use the
    /// short/long side so portrait (rotated) rects keep their detail.
    @ViewBuilder
    private func label(for display: DisplaySnapshot, in size: CGSize) -> some View {
        let shortSide = min(size.width, size.height)
        let longSide = max(size.width, size.height)
        if shortSide >= 30 && longSide >= 56 {
            VStack(spacing: 1) {
                Text(display.name)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("\(display.mode.width)×\(display.mode.height)")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if display.isMain {
                    Text(l("display_main"))
                        .font(.system(size: 8))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(2)
        } else if shortSide >= 16 && longSide >= 30 {
            Text(display.name)
                .font(.system(size: 8, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(1)
        } else if display.isMain {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 4, height: 4)
        }
    }
}

private extension View {
    /// Attaches a context menu only when `enabled`, so a read-only map shows none.
    @ViewBuilder
    func optionalContextMenu<Menu: View>(_ enabled: Bool, @ViewBuilder content: () -> Menu) -> some View {
        if enabled {
            contextMenu(menuItems: content)
        } else {
            self
        }
    }
}
