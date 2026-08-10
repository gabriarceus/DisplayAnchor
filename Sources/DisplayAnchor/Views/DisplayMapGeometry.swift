import CoreGraphics

/// Bidirectional mapping between display global coordinates and a view's local
/// coordinates. Scales a set of footprints to fit `size` while preserving aspect
/// ratio, then centers them. Exposes the forward transform (display → view) for
/// rendering and its inverse (view → display) needed to interpret drags.
struct DisplayMapGeometry {
    let scale: CGFloat
    private let minX: CGFloat
    private let minY: CGFloat
    private let offsetX: CGFloat
    private let offsetY: CGFloat

    /// Fits `footprints` (global-space rects) into `size` with `padding` on every
    /// edge. Degrades to an identity transform when there are no footprints.
    init(footprints: [CGRect], in size: CGSize, padding: CGFloat = 8) {
        guard !footprints.isEmpty else {
            scale = 1; minX = 0; minY = 0; offsetX = 0; offsetY = 0
            return
        }
        let originX = footprints.map(\.minX).min()!
        let originY = footprints.map(\.minY).min()!
        let totalWidth = max(footprints.map(\.maxX).max()! - originX, 1)
        let totalHeight = max(footprints.map(\.maxY).max()! - originY, 1)

        let availableWidth = max(size.width - padding * 2, 1)
        let availableHeight = max(size.height - padding * 2, 1)
        let fit = min(availableWidth / totalWidth, availableHeight / totalHeight)

        scale = fit
        minX = originX
        minY = originY
        offsetX = padding + (availableWidth - totalWidth * fit) / 2
        offsetY = padding + (availableHeight - totalHeight * fit) / 2
    }

    /// Display-space rect → view-space rect.
    func rect(for footprint: CGRect) -> CGRect {
        CGRect(
            x: offsetX + (footprint.minX - minX) * scale,
            y: offsetY + (footprint.minY - minY) * scale,
            width: footprint.width * scale,
            height: footprint.height * scale
        )
    }

    /// View-space length → display-space length.
    func displayLength(_ viewLength: CGFloat) -> CGFloat {
        viewLength / scale
    }
}
