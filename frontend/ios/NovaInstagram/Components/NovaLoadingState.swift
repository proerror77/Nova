import SwiftUI

// MARK: - Loading States

/// Full-screen loading overlay
struct NovaLoadingOverlay: View {
    var message: String = "加載中..."

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)

                Text(message)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.8))
            )
        }
    }
}

/// Inline loading spinner
struct NovaLoadingSpinner: View {
    var size: CGFloat = 24
    var color: Color = DesignColors.brandPrimary
    var lineWidth: CGFloat = 2

    var body: some View {
        ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: color))
            .scaleEffect(size / 20)
            .frame(width: size, height: size)
    }
}

/// Skeleton shimmer effect for loading placeholders
struct NovaShimmer: View {
    @State private var phase: CGFloat = 0
    var baseColor: Color = Color.gray.opacity(0.2)
    var highlightColor: Color = Color.gray.opacity(0.05)

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            baseColor,
                            highlightColor,
                            baseColor
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

// MARK: - Skeleton Screens

/// Skeleton for post card
struct NovaPostCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header skeleton
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 44, height: 44)
                    .overlay(NovaShimmer())
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 120, height: 12)
                        .overlay(NovaShimmer())
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 80, height: 10)
                        .overlay(NovaShimmer())
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Spacer()
            }
            .padding(12)

            // Image skeleton
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 300)
                .overlay(NovaShimmer())

            // Actions skeleton
            HStack(spacing: 12) {
                ForEach(0..<4) { _ in
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 24, height: 24)
                        .overlay(NovaShimmer())
                        .clipShape(Circle())
                }
            }
            .padding(12)

            // Text skeleton
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 150, height: 10)
                    .overlay(NovaShimmer())
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 12)
                    .overlay(NovaShimmer())
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .padding(12)
        }
        .background(DesignColors.surfaceElevated)
        .cornerRadius(8)
        .padding(.horizontal, 8)
    }
}

/// Skeleton for user list item
struct NovaUserListSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay(NovaShimmer())
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 140, height: 14)
                    .overlay(NovaShimmer())
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 100, height: 12)
                    .overlay(NovaShimmer())
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Spacer()

            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 80, height: 32)
                .overlay(NovaShimmer())
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// Generic skeleton placeholder
struct NovaSkeletonBox: View {
    var width: CGFloat? = nil
    var height: CGFloat
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.gray.opacity(0.2))
            .frame(width: width, height: height)
            .overlay(NovaShimmer())
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Pull to Refresh Indicator

struct NovaPullToRefreshIndicator: View {
    var isRefreshing: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isRefreshing {
                NovaLoadingSpinner(size: 20)
                Text("刷新中...")
                    .font(.system(size: 14))
                    .foregroundColor(DesignColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

// MARK: - Preview

#if DEBUG
struct NovaLoadingState_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Loading Overlay")
                    .font(.headline)
                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.1))
                        .frame(height: 100)
                    NovaLoadingOverlay(message: "正在處理...")
                }

                Text("Loading Spinner")
                    .font(.headline)
                HStack(spacing: 16) {
                    NovaLoadingSpinner(size: 20)
                    NovaLoadingSpinner(size: 32)
                    NovaLoadingSpinner(size: 44)
                }

                Text("Post Card Skeleton")
                    .font(.headline)
                NovaPostCardSkeleton()

                Text("User List Skeleton")
                    .font(.headline)
                NovaUserListSkeleton()

                Text("Generic Skeletons")
                    .font(.headline)
                VStack(spacing: 12) {
                    NovaSkeletonBox(width: 200, height: 20)
                    NovaSkeletonBox(height: 100)
                    HStack(spacing: 8) {
                        NovaSkeletonBox(height: 60)
                        NovaSkeletonBox(height: 60)
                        NovaSkeletonBox(height: 60)
                    }
                }
                .padding(.horizontal)

                Text("Pull to Refresh")
                    .font(.headline)
                NovaPullToRefreshIndicator(isRefreshing: true)
            }
            .padding(.vertical)
        }
        .background(DesignColors.surfaceLight)
    }
}
#endif
