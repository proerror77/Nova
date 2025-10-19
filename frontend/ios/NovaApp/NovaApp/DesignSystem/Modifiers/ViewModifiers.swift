import SwiftUI

// MARK: - Card Style Modifier
struct CardModifier: ViewModifier {
    var padding: CGFloat = Theme.Spacing.md
    var backgroundColor: Color = Theme.Colors.surface
    var shadow: (Color, CGFloat, CGFloat, CGFloat) = Theme.Shadows.small

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(backgroundColor)
            .cornerRadius(Theme.CornerRadius.md)
            .themeShadow(shadow)
    }
}

extension View {
    func cardStyle(
        padding: CGFloat = Theme.Spacing.md,
        backgroundColor: Color = Theme.Colors.surface,
        shadow: (Color, CGFloat, CGFloat, CGFloat) = Theme.Shadows.small
    ) -> some View {
        modifier(CardModifier(padding: padding, backgroundColor: backgroundColor, shadow: shadow))
    }
}

// MARK: - Shimmer Loading Modifier
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    .clear,
                                    Theme.Colors.skeletonHighlight.opacity(0.6),
                                    .clear
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .offset(x: -geometry.size.width + phase)
                        .onAppear {
                            withAnimation(
                                .linear(duration: 1.5)
                                .repeatForever(autoreverses: false)
                            ) {
                                phase = geometry.size.width * 2
                            }
                        }
                }
            )
            .clipped()
    }
}

extension View {
    func shimmerLoading() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Conditional Modifier
extension View {
    @ViewBuilder
    func `if`<Transform: View>(
        _ condition: Bool,
        transform: (Self) -> Transform
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Keyboard Dismissal
extension View {
    func hideKeyboardOnTap() -> some View {
        self.onTapGesture {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }
    }
}

// MARK: - Safe Area Inset Bottom (for tab bar)
extension View {
    func safeBottomPadding() -> some View {
        self.padding(.bottom, UIApplication.shared.windows.first?.safeAreaInsets.bottom ?? 0)
    }
}

// MARK: - Adaptive Stack (VStack on portrait, HStack on landscape)
struct AdaptiveStack<Content: View>: View {
    @Environment(\.verticalSizeClass) var verticalSizeClass
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat = Theme.Spacing.md, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        Group {
            if verticalSizeClass == .regular {
                VStack(spacing: spacing) {
                    content
                }
            } else {
                HStack(spacing: spacing) {
                    content
                }
            }
        }
    }
}

// MARK: - Haptic Feedback
extension View {
    func hapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) -> some View {
        self.onTapGesture {
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.impactOccurred()
        }
    }
}

#Preview {
    VStack(spacing: 32) {
        // Card style
        Text("Card Example")
            .cardStyle()

        // Shimmer loading
        Rectangle()
            .fill(Theme.Colors.skeletonBase)
            .frame(height: 100)
            .shimmerLoading()
            .cornerRadius(Theme.CornerRadius.md)

        // Adaptive stack
        AdaptiveStack {
            Text("Item 1")
            Text("Item 2")
            Text("Item 3")
        }
    }
    .padding()
}
