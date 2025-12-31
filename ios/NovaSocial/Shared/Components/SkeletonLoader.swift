import SwiftUI

// MARK: - Reusable Skeleton Loader Components

/// Base shimmer effect view
struct ShimmerEffect: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.gray.opacity(0.15),
                            Color.gray.opacity(0.25),
                            Color.gray.opacity(0.15)
                        ]),
                        startPoint: .init(x: phase - 0.5, y: 0.5),
                        endPoint: .init(x: phase + 0.5, y: 0.5)
                    )
                )
                .onAppear {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        phase = 1.5
                    }
                }
        }
    }
}

// MARK: - User Row Skeleton

/// Skeleton loader for user row items (following/followers lists)
struct UserRowSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            // Avatar skeleton
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay(ShimmerEffect())
                .clipShape(Circle())

            // Name skeleton
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 120, height: 16)
                    .overlay(ShimmerEffect())

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 80, height: 12)
                    .overlay(ShimmerEffect())
            }

            Spacer()

            // Button skeleton
            RoundedRectangle(cornerRadius: 46)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 85, height: 32)
                .overlay(ShimmerEffect())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Message Row Skeleton

/// Skeleton loader for chat message items
struct MessageRowSkeleton: View {
    let isFromMe: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if !isFromMe {
                // Avatar for other user
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .overlay(ShimmerEffect())
                    .clipShape(Circle())
            } else {
                Spacer()
            }

            // Message bubble skeleton
            VStack(alignment: isFromMe ? .trailing : .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: CGFloat.random(in: 150...260), height: 44)
                    .overlay(ShimmerEffect())
            }

            if isFromMe {
                // Avatar for me
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .overlay(ShimmerEffect())
                    .clipShape(Circle())
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Generic List Skeleton

/// Generic skeleton loader showing multiple placeholder items
struct SkeletonListLoader<Content: View>: View {
    var itemCount: Int = 5
    @ViewBuilder var itemBuilder: () -> Content

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(0..<itemCount, id: \.self) { _ in
                itemBuilder()
            }
        }
    }
}
