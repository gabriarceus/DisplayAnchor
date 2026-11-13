import CoreGraphics
import Foundation

/// One display being rearranged in the layout editor. A draft decoupled from the
/// live system: dragging mutates `origin` only, and nothing is applied until the
/// user commits. `size` is the on-screen footprint (the mode size, which already
/// follows the display's rotation) so snapping and overlap use the visible rect.
struct DraftDisplay: Identifiable, Equatable {
    let stableID: StableDisplayID
    let name: String
    var origin: CGPoint
    let size: CGSize
    var isMain: Bool

    var id: String { stableID.snapshotKey }
    var frame: CGRect { CGRect(origin: origin, size: size) }
}

/// Pure (view-free) helpers for interactive layout edits: seeding drafts from a
/// snapshot, snapping a dragged display against its neighbours, resolving
/// overlaps, turning a display, and rebuilding a `LayoutProfile` to feed the
/// apply engine.
enum LayoutEditing {

    /// Builds editable drafts from a live snapshot, using each display's visible
    /// footprint (the mode size, which already follows the display's rotation).
    static func seed(from displays: [DisplaySnapshot]) -> [DraftDisplay] {
        displays.map { d in
            DraftDisplay(
                stableID: d.stableID,
                name: d.name,
                origin: CGPoint(x: d.originX, y: d.originY),
                size: CGSize(width: CGFloat(max(d.mode.width, 1)), height: CGFloat(max(d.mode.height, 1))),
                isMain: d.isMain
            )
        }
    }

    /// Returns a snapped origin for `dragged`: each axis independently aligns to,
    /// or comes flush against, the nearest neighbour edge within `threshold`
    /// (display points). Size is preserved.
    static func snap(_ dragged: CGRect, among others: [CGRect], threshold: CGFloat) -> CGPoint {
        var bestX: (dist: CGFloat, value: CGFloat)?
        var bestY: (dist: CGFloat, value: CGFloat)?

        func considerX(_ candidate: CGFloat) {
            let dist = abs(candidate - dragged.minX)
            if dist <= threshold, bestX == nil || dist < bestX!.dist { bestX = (dist, candidate) }
        }
        func considerY(_ candidate: CGFloat) {
            let dist = abs(candidate - dragged.minY)
            if dist <= threshold, bestY == nil || dist < bestY!.dist { bestY = (dist, candidate) }
        }

        for other in others {
            // Horizontal: come flush to a side, or align left/right edges.
            considerX(other.maxX)  // dragged.left  == other.right
            considerX(other.minX - dragged.width)  // dragged.right == other.left
            considerX(other.minX)  // left edges aligned
            considerX(other.maxX - dragged.width)  // right edges aligned
            // Vertical: come flush above/below, or align top/bottom edges.
            considerY(other.maxY)  // dragged.top    == other.bottom
            considerY(other.minY - dragged.height)  // dragged.bottom == other.top
            considerY(other.minY)  // top edges aligned
            considerY(other.maxY - dragged.height)  // bottom edges aligned
        }

        return CGPoint(x: bestX?.value ?? dragged.minX, y: bestY?.value ?? dragged.minY)
    }

    /// Nudges `dragged` out of any overlap, pushing along the axis of least
    /// penetration to the nearer side until it sits clear of every neighbour.
    static func resolveOverlap(_ dragged: CGRect, among others: [CGRect]) -> CGPoint {
        var rect = dragged
        for _ in 0...others.count {
            guard let hit = others.first(where: { $0.intersects(rect) }) else { break }
            let overlap = rect.intersection(hit)
            if overlap.width <= overlap.height {
                rect.origin.x = rect.midX < hit.midX ? hit.minX - rect.width : hit.maxX
            } else {
                rect.origin.y = rect.midY < hit.midY ? hit.minY - rect.height : hit.maxY
            }
        }
        return rect.origin
    }

    /// Whether every frame is linked to the others through shared edges of positive
    /// length, as macOS requires for an arrangement. Corner contact does not count.
    static func isConnected(_ frames: [CGRect]) -> Bool {
        guard var pending = frames.indices.first.map({ [$0] }) else { return true }
        var reached: Set<Int> = Set(pending)
        while let index = pending.popLast() {
            for other in frames.indices where !reached.contains(other) && sharesEdge(frames[index], frames[other]) {
                reached.insert(other)
                pending.append(other)
            }
        }
        return reached.count == frames.count
    }

    /// Returns the origin nearest to `dragged` that places it flush against a
    /// neighbour, clear of every other frame, with the whole arrangement connected.
    /// The shared edge is at least `minimumSharedEdge` long, or the shorter side when
    /// that is less. Returns nil when no such position exists.
    static func attach(_ dragged: CGRect, among others: [CGRect], minimumSharedEdge: CGFloat) -> CGPoint? {
        var candidates: [CGPoint] = []
        for other in others {
            let overlapY = min(minimumSharedEdge, dragged.height, other.height)
            let overlapX = min(minimumSharedEdge, dragged.width, other.width)
            let y = min(max(dragged.minY, other.minY - dragged.height + overlapY), other.maxY - overlapY)
            let x = min(max(dragged.minX, other.minX - dragged.width + overlapX), other.maxX - overlapX)
            candidates += [
                CGPoint(x: other.maxX, y: y),  // right of other
                CGPoint(x: other.minX - dragged.width, y: y),  // left of other
                CGPoint(x: x, y: other.maxY),  // below other
                CGPoint(x: x, y: other.minY - dragged.height),  // above other
            ]
        }
        return
            candidates
            .filter { origin in
                let rect = CGRect(origin: origin, size: dragged.size)
                return !others.contains { !$0.intersection(rect).isEmpty } && isConnected(others + [rect])
            }
            .min { hypot($0.x - dragged.minX, $0.y - dragged.minY) < hypot($1.x - dragged.minX, $1.y - dragged.minY) }
    }

    /// Shortest shared edge, in display points, when a display is moved next to a neighbour.
    static let minimumSharedEdge: CGFloat = 200

    /// `displays` with the display keyed `snapshotKey` turned to `degrees`. A turn
    /// between landscape and portrait swaps its mode dimensions and moves the displays
    /// to its right or below it by the size change. If the arrangement is then
    /// detached, the turned display moves to the nearest origin that connects it.
    static func rotating(_ displays: [DisplaySnapshot], snapshotKey: String, to degrees: Int) -> [DisplaySnapshot] {
        guard let index = displays.firstIndex(where: { $0.stableID.snapshotKey == snapshotKey }) else {
            return displays
        }
        var displays = displays
        let isQuarterTurn = (Int(displays[index].rotation.rounded()) - degrees) % 180 != 0
        displays[index].rotation = Double(degrees)
        guard isQuarterTurn else { return displays }

        let old = seed(from: displays)[index].frame
        var mode = displays[index].mode
        swap(&mode.width, &mode.height)
        swap(&mode.pixelWidth, &mode.pixelHeight)
        displays[index].mode = mode
        for other in displays.indices where other != index {
            if CGFloat(displays[other].originX) >= old.maxX { displays[other].originX += Int(old.height - old.width) }
            if CGFloat(displays[other].originY) >= old.maxY { displays[other].originY += Int(old.width - old.height) }
        }

        var frames = seed(from: displays).map(\.frame)
        let turned = frames.remove(at: index)
        if !isConnected(frames + [turned]),
            let origin = attach(turned, among: frames, minimumSharedEdge: minimumSharedEdge)
        {
            displays[index].originX = Int(origin.x.rounded())
            displays[index].originY = Int(origin.y.rounded())
        }
        return displays
    }

    /// Whether `a` and `b` touch along an edge segment of positive length.
    private static func sharesEdge(_ a: CGRect, _ b: CGRect) -> Bool {
        // Half a point absorbs rounding from the map transform.
        let tolerance: CGFloat = 0.5
        let overlapX = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        let overlapY = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        let touchX = abs(a.maxX - b.minX) <= tolerance || abs(b.maxX - a.minX) <= tolerance
        let touchY = abs(a.maxY - b.minY) <= tolerance || abs(b.maxY - a.minY) <= tolerance
        return (touchX && overlapY > tolerance) || (touchY && overlapX > tolerance)
    }

    /// Rebuilds a `LayoutProfile` from the draft, carrying mode / mirror /
    /// rotation from the matching base snapshots and overriding origin + isMain.
    /// Displays whose identity is missing from `base` are dropped.
    static func profile(from draft: [DraftDisplay], base: [DisplaySnapshot], fingerprint: String) -> LayoutProfile {
        let byKey = Dictionary(base.map { ($0.stableID.snapshotKey, $0) }, uniquingKeysWith: { first, _ in first })
        let displays: [DisplaySnapshot] = draft.compactMap { d in
            guard var snapshot = byKey[d.id] else { return nil }
            snapshot.originX = Int(d.origin.x.rounded())
            snapshot.originY = Int(d.origin.y.rounded())
            snapshot.isMain = d.isMain
            return snapshot
        }
        return LayoutProfile(fingerprint: fingerprint, label: "", savedAt: Date(), displays: displays)
    }
}
