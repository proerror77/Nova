import SwiftUI

/// Full-screen loading overlay
struct LoadingView: View {
    var message: String = "Loading..."

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.md) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)

                Text(message)
                    .font(Theme.Typography.body)
                    .foregroundColor(.white)
            }
            .padding(Theme.Spacing.xl)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                    .fill(Color.black.opacity(0.8))
            )
        }
    }
}

/// Inline loading spinner
struct LoadingSpinner: View {
    var size: CGFloat = 24
    var color: Color = Theme.Colors.primary

    var body: some View {
        ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: color))
            .scaleEffect(size / 20)
            .frame(width: size, height: size)
    }
}

/// Skeleton shimmer effect
struct ShimmerView: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Theme.Colors.skeletonBase,
                            Theme.Colors.skeletonHighlight,
                            Theme.Colors.skeletonBase
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
    }
}

#Preview {
    VStack(spacing: 32) {
        LoadingView(message: "Processing...")

        LoadingSpinner()

        ShimmerView()
            .frame(height: 100)
            .cornerRadius(Theme.CornerRadius.md)
    }
    .padding()
}
