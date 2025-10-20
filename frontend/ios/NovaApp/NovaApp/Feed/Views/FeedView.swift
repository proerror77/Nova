import SwiftUI

/// F01 - Home Feed with infinite scroll + skeleton loader + error handling
struct FeedView: View {
    @StateObject private var viewModel = FeedViewModel()
    @EnvironmentObject var coordinator: NavigationCoordinator
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.md) {
                    // Network status banner
                    if viewModel.isOffline {
                        ErrorBanner(
                            message: "You're offline. Some features may be limited.",
                            onDismiss: {}
                        )
                        .padding(.horizontal, Theme.Spacing.md)
                    }

                    // Error banner
                    if viewModel.showError, let error = viewModel.error {
                        ErrorBanner(
                            message: error.localizedDescription,
                            onDismiss: {
                                viewModel.clearError()
                            }
                        )
                        .padding(.horizontal, Theme.Spacing.md)
                    }

                    if viewModel.isLoading && viewModel.posts.isEmpty {
                        // Skeleton loader for initial load
                        ForEach(0..<5) { _ in
                            SkeletonPostCard()
                        }
                    } else if !viewModel.isLoading && viewModel.posts.isEmpty {
                        // Empty state
                        EmptyStateView(
                            icon: "photo.on.rectangle.angled",
                            title: "No Posts Yet",
                            description: "Follow people to see their posts here"
                        )
                        .padding(.top, Theme.Spacing.xxl)
                    } else {
                        // Posts
                        ForEach(viewModel.posts) { post in
                            PostCard(
                                post: post,
                                onTap: {
                                    coordinator.navigate(to: .postDetail(postId: post.id))
                                    AnalyticsTracker.shared.track(.postTap(postId: post.id))
                                },
                                onLike: {
                                    Task {
                                        await viewModel.toggleLike(postId: post.id)
                                    }
                                },
                                onComment: {
                                    coordinator.navigate(to: .comments(postId: post.id))
                                }
                            )
                            .onAppear {
                                // Track impression
                                AnalyticsTracker.shared.track(.postImpression(postId: post.id))

                                // 智能预加载：预加载可见范围前后的图像
                                viewModel.handlePostAppear(post)

                                // Pagination trigger
                                if post.id == viewModel.posts.last?.id {
                                    Task {
                                        await viewModel.loadMore()
                                    }
                                }
                            }
                        }

                        // Loading indicator for pagination
                        if viewModel.isLoadingMore {
                            LoadingSpinner()
                                .padding()
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
            }
            .background(Theme.Colors.background)
            .refreshable {
                await viewModel.refresh()
            }
        }
        .onAppear {
            if viewModel.posts.isEmpty {
                Task {
                    await viewModel.loadInitial()
                }
            }
            AnalyticsTracker.shared.track(.feedView)

            // 启动性能监控
            PerformanceMonitor.shared.startMonitoring()
            PerformanceMonitor.shared.markFirstFrame()
            PerformanceMonitor.shared.logEvent("FeedView appeared")
        }
        .onDisappear {
            // 停止性能监控并生成报告
            PerformanceMonitor.shared.logEvent("FeedView disappeared")
            let report = PerformanceMonitor.shared.generateReport()
            print(report.summary)

            if !report.isHealthy {
                print("⚠️ Performance warning: Feed performance below threshold")
            }
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        #if DEBUG
        .performanceOverlay(enabled: true)  // 仅在 Debug 模式显示性能监控浮层
        #endif
    }
}

// MARK: - Skeleton Post Card
struct SkeletonPostCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Header skeleton
            HStack(spacing: Theme.Spacing.xs) {
                Circle()
                    .fill(Theme.Colors.skeletonBase)
                    .frame(width: Theme.AvatarSize.sm, height: Theme.AvatarSize.sm)
                VStack(alignment: .leading, spacing: 4) {
                    SkeletonView()
                        .frame(width: 100, height: 12)
                    SkeletonView()
                        .frame(width: 60, height: 10)
                }
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)

            // Image skeleton
            SkeletonView()
                .aspectRatio(1, contentMode: .fit)

            // Actions skeleton
            HStack(spacing: Theme.Spacing.md) {
                SkeletonView()
                    .frame(width: 40, height: 16)
                SkeletonView()
                    .frame(width: 40, height: 16)
            }
            .padding(.horizontal, Theme.Spacing.md)
        }
        .background(Theme.Colors.surface)
        .cornerRadius(Theme.CornerRadius.md)
        .themeShadow(Theme.Shadows.small)
    }
}

#Preview {
    NavigationStack {
        FeedView()
            .environmentObject(NavigationCoordinator())
            .environmentObject(AppState.shared)
    }
}
