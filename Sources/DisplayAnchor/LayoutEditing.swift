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

    var id: String { stableID.identityKey }
    var frame: CGRect { CGRect(origin: origin, size: size) }
}

/// Pure (view-free) helpers for the interactive layout editor: seeding drafts
/// from a snapshot, snapping a dragged display against its neighbours, resolving
/// overlaps, and rebuilding a `LayoutProfile` to feed the apply engine.
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
            considerX(other.maxX)                     // dragged.left  == other.right
            considerX(other.minX - dragged.width)     // dragged.right == other.left
            considerX(other.minX)                     // left edges aligned
            considerX(other.maxX - dragged.width)     // right edges aligned
            // Vertical: come flush above/below, or align top/bottom edges.
            considerY(other.maxY)                     // dragged.top    == other.bottom
            considerY(other.minY - dragged.height)    // dragged.bottom == other.top
            considerY(other.minY)                     // top edges aligned
            considerY(other.maxY - dragged.height)    // bottom edges aligned
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

    /// Rebuilds a `LayoutProfile` from the draft, carrying mode / mirror /
    /// rotation from the matching base snapshots and overriding origin + isMain.
    /// Displays whose identity is missing from `base` are dropped.
    static func profile(from draft: [DraftDisplay], base: [DisplaySnapshot], fingerprint: String) -> LayoutProfile {
        let byIdentity = Dictionary(base.map { ($0.stableID.identityKey, $0) }, uniquingKeysWith: { first, _ in first })
        let displays: [DisplaySnapshot] = draft.compactMap { d in
            guard var snapshot = byIdentity[d.stableID.identityKey] else { return nil }
            snapshot.originX = Int(d.origin.x.rounded())
            snapshot.originY = Int(d.origin.y.rounded())
            snapshot.isMain = d.isMain
            return snapshot
        }
        return LayoutProfile(fingerprint: fingerprint, label: "", savedAt: Date(), displays: displays)
    }
}
