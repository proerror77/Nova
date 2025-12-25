import SwiftUI

/// Animated typing dots indicator
struct TypingDotsView: View {
    @State private var animationPhase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(DesignTokens.textMuted)
                    .frame(width: 6, height: 6)
                    .offset(y: animationPhase == index ? -4 : 0)
            }
        }
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) {
                animationPhase = (animationPhase + 1) % 3
            }
        }
    }
}
