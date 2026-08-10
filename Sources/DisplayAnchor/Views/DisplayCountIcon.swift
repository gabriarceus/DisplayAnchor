import AppKit

/// Renders a template icon of side-by-side rounded rectangles representing the
/// connected displays. A single drawing source shared by the menu bar (AppKit)
/// and the SwiftUI views, so they stay visually identical. Rectangles are ordered
/// left-to-right by horizontal position; the main display is filled, the rest are
/// outlined.
enum DisplayCountIcon {
    /// Largest number of rectangles drawn; higher counts are clamped to this.
    static let maxRects = 4

    /// Template `NSImage` of one rectangle per display (clamped to `1...maxRects`),
    /// sized to sit in the menu bar or inline with text at `pointSize`.
    static func image(displays: [DisplaySnapshot], pointSize: CGFloat = 14) -> NSImage {
        let ordered = displays.sorted { ($0.originX, $0.originY) < ($1.originX, $1.originY) }
        let rectCount = min(max(ordered.count, 1), maxRects)
        let mainIndex = ordered.prefix(rectCount).firstIndex(where: { $0.isMain })

        let height = pointSize
        let rectWidth = pointSize * 0.46
        let gap = pointSize * 0.16
        let lineWidth = max(pointSize * 0.08, 1)
        let width = CGFloat(rectCount) * rectWidth + CGFloat(rectCount - 1) * gap + lineWidth

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            let rectHeight = height * 0.62
            let y = (height - rectHeight) / 2
            let inset = lineWidth / 2
            let corner = pointSize * 0.12

            for index in 0..<rectCount {
                let x = inset + CGFloat(index) * (rectWidth + gap)
                let frame = NSRect(x: x, y: y, width: rectWidth - lineWidth, height: rectHeight)
                let path = NSBezierPath(roundedRect: frame, xRadius: corner, yRadius: corner)
                NSColor.black.setStroke()
                NSColor.black.setFill()
                path.lineWidth = lineWidth
                if index == mainIndex { path.fill() } else { path.stroke() }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
