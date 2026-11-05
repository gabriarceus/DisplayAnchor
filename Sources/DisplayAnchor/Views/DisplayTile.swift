import SwiftUI

/// Rounded rectangle that stands for one display on a map. The main display gets
/// an accent fill and border; other displays use neutral tones at the given opacities.
/// The tile is also its own hit shape.
struct DisplayTile: View {
    let isMain: Bool
    let fillOpacity: Double
    let borderOpacity: Double
    let mainBorderWidth: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4)
        shape
            .fill(isMain ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(fillOpacity))
            .overlay(
                shape.strokeBorder(
                    isMain ? Color.accentColor : Color.secondary.opacity(borderOpacity),
                    lineWidth: isMain ? mainBorderWidth : 1
                )
            )
            .contentShape(shape)
    }
}
