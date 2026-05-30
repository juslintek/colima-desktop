import SwiftUI

struct HoverHighlight: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
            )
            .onHover { isHovered = $0 }
    }
}

extension View {
    func hoverHighlight() -> some View {
        modifier(HoverHighlight())
    }
}
