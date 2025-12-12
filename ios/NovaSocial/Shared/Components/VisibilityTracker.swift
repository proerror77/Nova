import SwiftUI

/// A view modifier that tracks visibility in a scroll view
struct VisibilityTracker: ViewModifier {
    let id: String
    let threshold: CGFloat
    let onVisibilityChange: (Bool) -> Void

    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: VisibilityPreferenceKey.self,
                            value: [VisibilityItem(id: id, frame: geometry.frame(in: .global))]
                        )
                }
            )
            .onPreferenceChange(VisibilityPreferenceKey.self) { items in
                guard let item = items.first(where: { $0.id == id }) else { return }

                let screenHeight = UIScreen.main.bounds.height
                let visibleHeight = min(item.frame.maxY, screenHeight) - max(item.frame.minY, 0)
                let itemHeight = item.frame.height

                let visibilityRatio = itemHeight > 0 ? visibleHeight / itemHeight : 0
                let newVisibility = visibilityRatio >= threshold

                if newVisibility != isVisible {
                    isVisible = newVisibility
                    onVisibilityChange(newVisibility)
                }
            }
    }
}

struct VisibilityItem: Equatable {
    let id: String
    let frame: CGRect
}

struct VisibilityPreferenceKey: PreferenceKey {
    static var defaultValue: [VisibilityItem] = []

    static func reduce(value: inout [VisibilityItem], nextValue: () -> [VisibilityItem]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    /// Track visibility with a threshold (0.0 to 1.0)
    func trackVisibility(
        id: String,
        threshold: CGFloat = 0.5,
        onVisibilityChange: @escaping (Bool) -> Void
    ) -> some View {
        modifier(VisibilityTracker(id: id, threshold: threshold, onVisibilityChange: onVisibilityChange))
    }
}
