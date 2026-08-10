import SwiftUI

/// Hover tooltip with a short appearance delay. Replaces `.help(_:)`, whose
/// appearance delay is the (slow) system default and not configurable.
///
/// The hovered control only publishes the tooltip text and its frame through a
/// preference; the bubble itself is drawn once at the panel root (see
/// `hoverTipHost()`), so it escapes any `ScrollView`/container clipping and is
/// clamped to stay inside the panel.

struct HoverTipValue: Equatable {
    let text: String
    let anchor: Anchor<CGRect>
}

struct HoverTipKey: PreferenceKey {
    static let defaultValue: HoverTipValue? = nil
    static func reduce(value: inout HoverTipValue?, nextValue: () -> HoverTipValue?) {
        if let next = nextValue() { value = next }
    }
}

private struct HoverTip: ViewModifier {
    let text: String

    @State private var show = false
    @State private var task: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                task?.cancel()
                if hovering {
                    task = Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        if !Task.isCancelled { show = true }
                    }
                } else {
                    show = false
                }
            }
            .anchorPreference(key: HoverTipKey.self, value: .bounds) { anchor in
                show ? HoverTipValue(text: text, anchor: anchor) : nil
            }
            .accessibilityLabel(text)
    }
}

/// The bubble, positioned relative to its target and clamped within `container`.
private struct HoverTipBubble: View {
    let text: String
    let target: CGRect
    let container: CGSize

    @State private var size: CGSize = .zero

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.quaternary))
            .fixedSize()
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { size = proxy.size }
                    .onChange(of: proxy.size) { _, newValue in size = newValue }
            })
            .position(position)
            .opacity(size == .zero ? 0 : 1)
            .allowsHitTesting(false)
    }

    private var position: CGPoint {
        let margin: CGFloat = 4
        let halfW = size.width / 2
        let halfH = size.height / 2

        let x = min(max(target.midX, margin + halfW), container.width - margin - halfW)

        // Prefer above the target; fall back below when there isn't room.
        var y = target.minY - margin - halfH
        if y - halfH < margin { y = target.maxY + margin + halfH }
        y = min(max(y, margin + halfH), container.height - margin - halfH)

        return CGPoint(x: x, y: y)
    }
}

extension View {
    /// A fast-appearing hover tooltip. Drop-in replacement for `.help(_:)`.
    func hoverTip(_ text: String) -> some View {
        modifier(HoverTip(text: text))
    }

    /// Hosts the tooltip bubble for any `hoverTip(_:)` in the subtree. Apply once
    /// at the panel root so the bubble is never clipped by inner containers.
    func hoverTipHost() -> some View {
        overlayPreferenceValue(HoverTipKey.self) { value in
            GeometryReader { proxy in
                if let value {
                    HoverTipBubble(text: value.text, target: proxy[value.anchor], container: proxy.size)
                }
            }
            .allowsHitTesting(false)
        }
    }
}
