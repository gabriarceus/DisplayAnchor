import MenuBarKit
import SwiftUI

/// Drag-and-drop layout editor. Works on an in-memory draft seeded from the live
/// arrangement: dragging only mutates the draft, so the real displays stay
/// untouched until the user applies. The map geometry is frozen for the session
/// (computed from the seed bounds) so dragging never rescales the canvas. If the
/// connected set changes underneath the editor, it discards the draft and leaves.
struct LayoutEditorView: View {
    @ObservedObject var store: LayoutStore
    let onClose: () -> Void

    @Environment(\.localizer) private var l

    @State private var draft: [DraftDisplay] = []
    @State private var seed: [DraftDisplay] = []
    @State private var world = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var dragging: (id: String, start: CGPoint)?
    @State private var initialFingerprint = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            canvas
            Divider()
            footer
        }
        .frame(width: 340, height: 540)
        .onAppear(perform: load)
        .onChange(of: store.currentFingerprint) { _, newValue in
            // The connected set changed — the draft is stale; bail out safely.
            if newValue != initialFingerprint { onClose() }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text(l("editor_title")).font(.headline)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .hoverTip(l("editor_cancel_hint"))

            Button(action: apply) {
                Image(systemName: "checkmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(hasChanges ? Color.green : Color.secondary)
            .disabled(!hasChanges)
            .hoverTip(l("editor_apply_hint"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var canvas: some View {
        GeometryReader { geometry in
            let map = DisplayMapGeometry(footprints: [world], in: geometry.size, padding: 16)
            ZStack(alignment: .topLeading) {
                ForEach(draft) { display in
                    let rect = map.rect(for: display.frame)
                    displayRect(display, size: rect.size)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .zIndex(dragging?.id == display.id ? 1 : 0)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            // One canvas-level gesture instead of a gesture per rect: a per-rect
            // DragGesture on macOS is cancelled when the cursor leaves the moving
            // rect and fights with .contextMenu, so the (static) canvas owns the
            // drag and hit-tests which display it started on. Simultaneous, so it
            // never starves the rects' context-menu recognizers.
            .contentShape(Rectangle())
            .coordinateSpace(name: Self.canvasSpace)
            .simultaneousGesture(canvasDragGesture(map: map))
        }
    }

    private var footer: some View {
        Text(l("editor_description"))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
    }

    // MARK: - Display rect

    /// Rect content only — the caller frames and offsets it, mirroring
    /// `DisplayMapView`: the context menu must be attached before `offset`, or its
    /// hit region stays at the pre-offset position and right-clicks miss.
    @ViewBuilder
    private func displayRect(_ display: DraftDisplay, size: CGSize) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4)
        shape
            .fill(display.isMain ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.14))
            .overlay(
                shape.strokeBorder(
                    display.isMain ? Color.accentColor : Color.secondary.opacity(0.6),
                    lineWidth: display.isMain ? 2 : 1
                )
            )
            .overlay(label(for: display, in: size))
            .contentShape(shape)
            .contextMenu {
                Button(l("display_set_main")) { setMain(display.id) }
                    .disabled(display.isMain)
            }
    }

    @ViewBuilder
    private func label(for display: DraftDisplay, in size: CGSize) -> some View {
        if min(size.width, size.height) >= 26 && max(size.width, size.height) >= 44 {
            VStack(spacing: 1) {
                Text(display.name)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if display.isMain {
                    Text(l("display_main"))
                        .font(.system(size: 8))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(2)
        }
    }

    // MARK: - Drag

    private static let canvasSpace = "editorCanvas"

    private func canvasDragGesture(map: DisplayMapGeometry) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.canvasSpace))
            .onChanged { value in
                if dragging == nil {
                    // Topmost hit wins: later drafts draw above earlier ones.
                    guard let hit = draft.last(where: { map.rect(for: $0.frame).contains(value.startLocation) })
                    else { return }
                    dragging = (hit.id, hit.origin)
                }
                guard let (id, start) = dragging,
                      let display = draft.first(where: { $0.id == id }) else { return }
                let moved = CGPoint(
                    x: start.x + map.displayLength(value.translation.width),
                    y: start.y + map.displayLength(value.translation.height)
                )
                let others = otherFrames(excluding: id)
                let snapped = LayoutEditing.snap(CGRect(origin: moved, size: display.size),
                                                 among: others, threshold: map.displayLength(10))
                updateOrigin(id, to: snapped)
            }
            .onEnded { _ in
                if let id = dragging?.id, let index = draft.firstIndex(where: { $0.id == id }) {
                    let others = otherFrames(excluding: id)
                    var origin = LayoutEditing.snap(draft[index].frame, among: others, threshold: map.displayLength(10))
                    origin = LayoutEditing.resolveOverlap(CGRect(origin: origin, size: draft[index].size), among: others)
                    draft[index].origin = origin
                }
                dragging = nil
            }
    }

    // MARK: - Mutations

    private func load() {
        draft = LayoutEditing.seed(from: store.currentDisplays)
        seed = draft
        initialFingerprint = store.currentFingerprint
        let union = draft.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        world = union.isNull
            ? CGRect(x: 0, y: 0, width: 1, height: 1)
            : union.insetBy(dx: -union.width * 0.2, dy: -union.height * 0.2)
    }

    private func updateOrigin(_ id: String, to origin: CGPoint) {
        guard let index = draft.firstIndex(where: { $0.id == id }) else { return }
        draft[index].origin = origin
    }

    private func setMain(_ id: String) {
        for index in draft.indices {
            draft[index].isMain = draft[index].id == id
        }
    }

    private func otherFrames(excluding id: String) -> [CGRect] {
        draft.filter { $0.id != id }.map(\.frame)
    }

    private func apply() {
        store.applyEditedLayout(draft)
        onClose()
    }

    // MARK: - Derived

    private var hasChanges: Bool {
        guard draft.count == seed.count else { return true }
        for current in draft {
            guard let original = seed.first(where: { $0.id == current.id }) else { return true }
            if Int(current.origin.x.rounded()) != Int(original.origin.x.rounded()) { return true }
            if Int(current.origin.y.rounded()) != Int(original.origin.y.rounded()) { return true }
            if current.isMain != original.isMain { return true }
        }
        return false
    }
}
