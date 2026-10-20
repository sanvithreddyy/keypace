import SwiftUI

/// The exact value of the mark under the pointer, in a small label just above it.
/// Placed in the coordinate space of the view it fills, and kept inside that view's width.
struct HoverLabel: View {
    let text: String
    /// The hovered mark's frame.
    let target: CGRect

    var body: some View {
        Above(target: target) {
            Text(text)
                .font(.caption)
                .monospacedDigit()
                .fixedSize()
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color(nsColor: .windowBackgroundColor), in: .rect(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.quaternary))
        }
        // The label covers neighboring marks; the pointer must still reach them.
        .allowsHitTesting(false)
    }

    private struct Above: Layout {
        let target: CGRect

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            proposal.replacingUnspecifiedDimensions()
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            guard let label = subviews.first else { return }
            let size = label.sizeThatFits(.unspecified)
            let x = min(max(bounds.minX + target.midX - size.width / 2, bounds.minX), bounds.maxX - size.width)
            label.place(at: CGPoint(x: x, y: bounds.minY + target.minY - size.height - 4), proposal: ProposedViewSize(size))
        }
    }
}

extension View {
    /// Outlines this mark while the pointer is over it, and reports `text` to the enclosing `hoverValues()`.
    /// Marks without text don't respond.
    func hoverValue(_ text: String?, cornerRadius: CGFloat) -> some View {
        modifier(HoverValue(text: text, cornerRadius: cornerRadius))
    }

    /// Shows the label of whichever mark inside is hovered.
    func hoverValues() -> some View {
        overlayPreferenceValue(HoveredMark.self) { mark in
            GeometryReader { proxy in
                if let mark { HoverLabel(text: mark.text, target: proxy[mark.bounds]) }
            }
        }
    }
}

private struct HoverValue: ViewModifier {
    let text: String?
    let cornerRadius: CGFloat
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isHovered { RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color.primary, lineWidth: 1.5) }
            }
            .contentShape(.rect)
            .onHover { isHovered = $0 && text != nil }
            .anchorPreference(key: HoveredMark.self, value: .bounds) { bounds in
                text.flatMap { isHovered ? HoveredMark.Mark(bounds: bounds, text: $0) : nil }
            }
    }
}

private struct HoveredMark: PreferenceKey {
    struct Mark {
        var bounds: Anchor<CGRect>
        var text: String
    }

    static var defaultValue: Mark? { nil }

    static func reduce(value: inout Mark?, nextValue: () -> Mark?) {
        value = value ?? nextValue()
    }
}
