import SwiftUI

// MARK: - Custom Transitions
extension AnyTransition {
    /// Slide from bottom with fade
    static var slideFromBottom: AnyTransition {
        AnyTransition.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        )
    }

    /// Scale and fade
    static var scaleAndFade: AnyTransition {
        AnyTransition.scale.combined(with: .opacity)
    }

    /// Slide from trailing edge
    static var slideFromTrailing: AnyTransition {
        AnyTransition.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }
}

// MARK: - Animation Presets
extension Animation {
    /// Quick spring animation for UI feedback
    static var quickSpring: Animation {
        .spring(response: 0.3, dampingFraction: 0.7, blendDuration: 0)
    }

    /// Smooth easing animation
    static var smooth: Animation {
        .easeInOut(duration: 0.3)
    }

    /// Bouncy spring for playful interactions
    static var bouncy: Animation {
        .spring(response: 0.4, dampingFraction: 0.6, blendDuration: 0)
    }

    /// Gentle animation for subtle changes
    static var gentle: Animation {
        .easeOut(duration: 0.2)
    }
}

// MARK: - Animated View Modifiers
struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 10
    var shakesPerUnit = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(
                translationX: amount * sin(animatableData * .pi * CGFloat(shakesPerUnit)),
                y: 0
            )
        )
    }
}

extension View {
    /// Shake animation for errors
    func shake(trigger: Int) -> some View {
        modifier(ShakeEffect(animatableData: CGFloat(trigger)))
    }
}

// MARK: - Loading Pulse Animation
struct PulseModifier: ViewModifier {
    @State private var isAnimating = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isAnimating ? 1.05 : 1.0)
            .opacity(isAnimating ? 0.7 : 1.0)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.0)
                    .repeatForever(autoreverses: true)
                ) {
                    isAnimating = true
                }
            }
    }
}

extension View {
    func pulse() -> some View {
        modifier(PulseModifier())
    }
}

// MARK: - Hero Animation Helper
struct MatchedGeometryID {
    static let postImage = "postImage"
    static let profileAvatar = "profileAvatar"
    static let likeButton = "likeButton"
}

// MARK: - Preview
#Preview {
    VStack(spacing: 40) {
        // Shake effect demo
        Button("Shake Me") {}
            .padding()
            .background(Theme.Colors.primary)
            .foregroundColor(.white)
            .cornerRadius(Theme.CornerRadius.md)

        // Pulse effect demo
        Circle()
            .fill(Theme.Colors.primary)
            .frame(width: 60, height: 60)
            .pulse()

        // Spring animation demo
        Rectangle()
            .fill(Theme.Colors.primary)
            .frame(width: 100, height: 100)
            .cornerRadius(Theme.CornerRadius.md)
    }
}
