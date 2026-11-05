import AppKit

/// Renders a template icon of side-by-side rounded rectangles representing the
/// connected displays. A single drawing source shared by the menu bar (AppKit)
/// and the SwiftUI views, so they stay visually identical. Rectangles are ordered
/// left-to-right by horizontal position, scaled by each display's logical size, and
/// placed vertically as in the arrangement; the main display is filled, the rest are outlined.
enum DisplayCountIcon {
    /// Largest number of rectangles drawn; higher counts are clamped to this.
    static let maxRects = 4
    /// Smallest scale of a rectangle relative to the largest display, so tiny displays stay visible.
    static let minimumScale: CGFloat = 0.5

    /// Template `NSImage` of one rectangle per display (clamped to `1...maxRects`),
    /// sized to sit in the menu bar or inline with text at `pointSize`.
    static func image(displays: [DisplaySnapshot], pointSize: CGFloat = 14) -> NSImage {
        let lineWidth = max(pointSize * 0.08, 1)
        let rects = glyphRects(displays: displays, pointSize: pointSize)
        let mainIndex = ordered(displays).prefix(rects.count).firstIndex(where: { $0.isMain })
        let width = (rects.last?.maxX ?? 0) + lineWidth / 2

        let image = NSImage(size: NSSize(width: width, height: pointSize), flipped: false) { _ in
            let corner = pointSize * 0.12
            NSColor.black.setStroke()
            NSColor.black.setFill()
            for (index, outer) in rects.enumerated() {
                // Filled and outlined rectangles share the same outer bounds: the stroke is drawn inside them.
                if index == mainIndex {
                    NSBezierPath(roundedRect: outer, xRadius: corner, yRadius: corner).fill()
                } else {
                    let inset = lineWidth / 2
                    let path = NSBezierPath(
                        roundedRect: outer.insetBy(dx: inset, dy: inset), xRadius: corner - inset,
                        yRadius: corner - inset)
                    path.lineWidth = lineWidth
                    path.stroke()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Outer bounds of each rectangle in image coordinates (origin at the bottom left),
    /// left to right. Each rectangle is scaled by the display's long side relative to
    /// the largest display, and sits vertically where the display sits in the arrangement:
    /// a display aligned to the bottom of the others is drawn aligned to their bottom.
    static func glyphRects(displays: [DisplaySnapshot], pointSize: CGFloat) -> [CGRect] {
        let lineWidth = max(pointSize * 0.08, 1)
        let rectWidth = pointSize * 0.46
        let rectHeight = pointSize * 0.62 + lineWidth
        let gap = pointSize * 0.16
        let shown = Array(ordered(displays).prefix(maxRects))
        guard !shown.isEmpty else {
            return [CGRect(x: lineWidth / 2, y: (pointSize - rectHeight) / 2, width: rectWidth, height: rectHeight)]
        }
        let largest = CGFloat(shown.map { max($0.mode.width, $0.mode.height, 1) }.max() ?? 1)
        let top = shown.map(\.originY).min() ?? 0
        let bottom = shown.map { $0.originY + $0.mode.height }.max() ?? 0

        var x = lineWidth / 2
        return shown.map { display in
            let scale = max(CGFloat(max(display.mode.width, display.mode.height, 1)) / largest, minimumScale)
            let size = CGSize(width: rectWidth * scale, height: rectHeight * scale)
            // 0 when the display touches the top of the arrangement, 1 when it touches the bottom.
            let free = CGFloat(bottom - top - display.mode.height)
            let position = free > 0 ? min(max(CGFloat(display.originY - top) / free, 0), 1) : 0.5
            let y = (pointSize - rectHeight) / 2 + (1 - position) * (rectHeight - size.height)
            defer { x += size.width + gap }
            return CGRect(origin: CGPoint(x: x, y: y), size: size)
        }
    }

    private static func ordered(_ displays: [DisplaySnapshot]) -> [DisplaySnapshot] {
        displays.sorted { ($0.originX, $0.originY) < ($1.originX, $1.originY) }
    }
}
