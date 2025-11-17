import SwiftUI

// MARK: - Skeleton Loading View
/// 骨架屏加载视图 - 提供优雅的加载状态展示
/// 数据结构思考：简单的形状组合，无特殊情况分支
struct SkeletonLoadingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Skeleton
            HStack(spacing: 12) {
                SkeletonShape()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())

                SkeletonShape()
                    .frame(width: 120, height: 14)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 12)

            // Image Skeleton
            SkeletonShape()
                .aspectRatio(1, contentMode: .fill)

            // Actions Skeleton
            HStack(spacing: 16) {
                SkeletonShape()
                    .frame(width: 24, height: 24)

                SkeletonShape()
                    .frame(width: 24, height: 24)

                SkeletonShape()
                    .frame(width: 24, height: 24)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 12)

            // Caption Skeleton
            VStack(alignment: .leading, spacing: 8) {
                SkeletonShape()
                    .frame(height: 12)
                    .frame(maxWidth: .infinity)

                SkeletonShape()
                    .frame(height: 12)
                    .frame(maxWidth: 200)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
    }
}

// MARK: - Skeleton Shape with Animation
/// 基础骨架形状 - 带闪烁动画
/// 简单设计：单一职责，只负责显示和动画
struct SkeletonShape: View {
    @State private var isAnimating = false

    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .overlay(
                GeometryReader { geometry in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.clear,
                                    Color.white.opacity(0.6),
                                    Color.clear
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * 0.4)
                        .offset(x: isAnimating ? geometry.size.width : -geometry.size.width * 0.4)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .onAppear {
                withAnimation(
                    Animation.linear(duration: 1.5)
                        .repeatForever(autoreverses: false)
                ) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Modern Skeleton Shape (iOS 17+)
/// 现代骨架形状 - 使用更平滑的动画效果
@available(iOS 17.0, *)
struct ModernSkeletonShape: View {
    @State private var progress: Double = 0

    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.clear,
                            Color.white.opacity(0.8),
                            Color.clear
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 0.3)
                    .offset(x: progress * (geometry.size.width * 1.3) - geometry.size.width * 0.3)
                    .blur(radius: 8)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .onAppear {
                withAnimation(
                    Animation.linear(duration: 1.5)
                        .repeatForever(autoreverses: false)
                ) {
                    progress = 1.0
                }
            }
    }
}

// MARK: - Skeleton List
/// 骨架屏列表 - 用于 Feed 初始加载
struct SkeletonPostList: View {
    var count: Int = 3

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { _ in
                SkeletonLoadingView()
                Divider()
            }
        }
    }
}

// MARK: - Compact Skeleton (用于评论等小组件)
/// 紧凑型骨架 - 用于评论、通知等场景
struct CompactSkeletonView: View {
    var body: some View {
        HStack(spacing: 12) {
            SkeletonShape()
                .frame(width: 40, height: 40)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                SkeletonShape()
                    .frame(width: 100, height: 12)

                SkeletonShape()
                    .frame(height: 10)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding()
    }
}

// MARK: - Grid Skeleton (用于网格布局)
/// 网格骨架 - 用于 Explore 等网格场景
struct GridSkeletonView: View {
    var columns: Int = 3
    var rows: Int = 3

    private var gridItems: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 2), count: columns)
    }

    var body: some View {
        LazyVGrid(columns: gridItems, spacing: 2) {
            ForEach(0..<(columns * rows), id: \.self) { _ in
                SkeletonShape()
                    .aspectRatio(1, contentMode: .fill)
            }
        }
    }
}

// MARK: - Preview
#Preview("Post Skeleton") {
    ScrollView {
        SkeletonPostList(count: 2)
    }
}

#Preview("Compact Skeleton") {
    VStack(spacing: 0) {
        CompactSkeletonView()
        Divider()
        CompactSkeletonView()
        Divider()
        CompactSkeletonView()
    }
}

#Preview("Grid Skeleton") {
    GridSkeletonView(columns: 3, rows: 4)
}
