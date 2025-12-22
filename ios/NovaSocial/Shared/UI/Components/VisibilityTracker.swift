import SwiftUI

/// A view modifier that tracks visibility in a scroll view
struct VisibilityTracker: ViewModifier {
    let id: String
    let threshold: CGFloat
    let onVisibilityChange: (Bool) -> Void

    @State private var isVisible = false
    @State private var screenHeight: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: VisibilityPreferenceKey.self,
                            value: [VisibilityItem(
                                id: id,
                                frame: geometry.frame(in: .global),
                                screenHeight: geometry.frame(in: .global).height > 0 ?
                                    (geometry.frame(in: .global).maxY > screenHeight ? geometry.frame(in: .global).maxY : screenHeight) :
                                    screenHeight
                            )]
                        )
                        .onAppear {
                            // Capture screen height from global coordinate space
                            let globalFrame = geometry.frame(in: .global)
                            // Estimate screen height from the maximum Y value visible
                            if globalFrame.maxY > screenHeight {
                                screenHeight = globalFrame.maxY + globalFrame.minY
                            }
                        }
                }
            )
            .background(
                // Separate GeometryReader to get the screen bounds reliably
                GeometryReader { geo in
                    Color.clear.onAppear {
                        // Get a better estimate of screen height
                        let safeArea = geo.safeAreaInsets
                        let totalHeight = geo.size.height + safeArea.top + safeArea.bottom
                        if totalHeight > screenHeight {
                            screenHeight = totalHeight
                        }
                    }
                }
            )
            .onPreferenceChange(VisibilityPreferenceKey.self) { items in
                guard let item = items.first(where: { $0.id == id }) else { return }

                // Use the screen height from the preference if available, otherwise use state
                let effectiveScreenHeight = item.screenHeight > 0 ? item.screenHeight : screenHeight
                guard effectiveScreenHeight > 0 else { return }

                let visibleHeight = min(item.frame.maxY, effectiveScreenHeight) - max(item.frame.minY, 0)
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
    let screenHeight: CGFloat
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
