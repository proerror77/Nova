import SwiftUI

// MARK: - Refreshable List with Pull-to-Refresh

/// List wrapper with pull-to-refresh support
struct NovaRefreshableList<Content: View>: View {
    let content: Content
    let onRefresh: () async -> Void

    init(
        onRefresh: @escaping () async -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.onRefresh = onRefresh
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
        }
        .refreshable {
            await onRefresh()
        }
    }
}

// MARK: - Infinite Scroll List

/// List with pagination and infinite scroll
struct NovaInfiniteScrollList<Item: Identifiable, Content: View, LoadingContent: View>: View {
    let items: [Item]
    let isLoading: Bool
    let isLoadingMore: Bool
    let hasMore: Bool
    let onLoadMore: () async -> Void
    let content: (Item) -> Content
    let loadingContent: () -> LoadingContent

    // Threshold: trigger load more when user is this many items from the bottom
    var loadMoreThreshold: Int = 3

    init(
        items: [Item],
        isLoading: Bool = false,
        isLoadingMore: Bool = false,
        hasMore: Bool = true,
        loadMoreThreshold: Int = 3,
        onLoadMore: @escaping () async -> Void,
        @ViewBuilder content: @escaping (Item) -> Content,
        @ViewBuilder loadingContent: @escaping () -> LoadingContent = { NovaLoadingSpinner() }
    ) {
        self.items = items
        self.isLoading = isLoading
        self.isLoadingMore = isLoadingMore
        self.hasMore = hasMore
        self.loadMoreThreshold = loadMoreThreshold
        self.onLoadMore = onLoadMore
        self.content = content
        self.loadingContent = loadingContent
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    content(item)
                        .onAppear {
                            // Trigger load more when approaching the end
                            if shouldLoadMore(at: index) {
                                Task {
                                    await onLoadMore()
                                }
                            }
                        }
                }

                // Loading more indicator
                if isLoadingMore && hasMore {
                    HStack {
                        Spacer()
                        loadingContent()
                        Spacer()
                    }
                    .padding(.vertical, 20)
                }

                // End of list indicator
                if !hasMore && !items.isEmpty {
                    NovaEndOfListView()
                }
            }
        }
    }

    private func shouldLoadMore(at index: Int) -> Bool {
        // Don't trigger if already loading
        guard !isLoadingMore && !isLoading else { return false }

        // Don't trigger if no more items
        guard hasMore else { return false }

        // Trigger when user reaches threshold items from the end
        return index >= items.count - loadMoreThreshold
    }
}

// MARK: - Combined Refreshable + Infinite Scroll List

/// Complete list solution with pull-to-refresh and pagination
struct NovaEnhancedList<Item: Identifiable, Content: View, LoadingContent: View>: View {
    let items: [Item]
    let isLoading: Bool
    let isRefreshing: Bool
    let isLoadingMore: Bool
    let hasMore: Bool
    let onRefresh: () async -> Void
    let onLoadMore: () async -> Void
    let content: (Item) -> Content
    let loadingContent: () -> LoadingContent

    var loadMoreThreshold: Int = 3

    init(
        items: [Item],
        isLoading: Bool = false,
        isRefreshing: Bool = false,
        isLoadingMore: Bool = false,
        hasMore: Bool = true,
        loadMoreThreshold: Int = 3,
        onRefresh: @escaping () async -> Void,
        onLoadMore: @escaping () async -> Void,
        @ViewBuilder content: @escaping (Item) -> Content,
        @ViewBuilder loadingContent: @escaping () -> LoadingContent = { NovaLoadingSpinner() }
    ) {
        self.items = items
        self.isLoading = isLoading
        self.isRefreshing = isRefreshing
        self.isLoadingMore = isLoadingMore
        self.hasMore = hasMore
        self.loadMoreThreshold = loadMoreThreshold
        self.onRefresh = onRefresh
        self.onLoadMore = onLoadMore
        self.content = content
        self.loadingContent = loadingContent
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    content(item)
                        .onAppear {
                            if shouldLoadMore(at: index) {
                                Task {
                                    await onLoadMore()
                                }
                            }
                        }
                }

                // Loading more indicator
                if isLoadingMore && hasMore {
                    HStack {
                        Spacer()
                        loadingContent()
                        Spacer()
                    }
                    .padding(.vertical, 20)
                }

                // End of list indicator
                if !hasMore && !items.isEmpty {
                    NovaEndOfListView()
                }
            }
        }
        .refreshable {
            await onRefresh()
        }
    }

    private func shouldLoadMore(at index: Int) -> Bool {
        guard !isLoadingMore && !isLoading && !isRefreshing else { return false }
        guard hasMore else { return false }
        return index >= items.count - loadMoreThreshold
    }
}

// MARK: - List State Wrapper

/// Handles all list states: loading, loaded, empty, error
struct NovaStatefulList<Item: Identifiable, Content: View, EmptyContent: View, ErrorContent: View>: View {
    let state: ViewState<[Item]>
    let onRefresh: () async -> Void
    let onLoadMore: () async -> Void
    let isLoadingMore: Bool
    let hasMore: Bool
    let content: (Item) -> Content
    let emptyContent: () -> EmptyContent
    let errorContent: (Error) -> ErrorContent

    init(
        state: ViewState<[Item]>,
        isLoadingMore: Bool = false,
        hasMore: Bool = true,
        onRefresh: @escaping () async -> Void,
        onLoadMore: @escaping () async -> Void,
        @ViewBuilder content: @escaping (Item) -> Content,
        @ViewBuilder emptyContent: @escaping () -> EmptyContent,
        @ViewBuilder errorContent: @escaping (Error) -> ErrorContent
    ) {
        self.state = state
        self.isLoadingMore = isLoadingMore
        self.hasMore = hasMore
        self.onRefresh = onRefresh
        self.onLoadMore = onLoadMore
        self.content = content
        self.emptyContent = emptyContent
        self.errorContent = errorContent
    }

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                // Show skeleton loading
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(0..<5, id: \.self) { _ in
                            NovaPostCardSkeleton()
                        }
                    }
                }

            case .loaded(let items):
                if items.isEmpty {
                    emptyContent()
                } else {
                    NovaEnhancedList(
                        items: items,
                        isLoadingMore: isLoadingMore,
                        hasMore: hasMore,
                        onRefresh: onRefresh,
                        onLoadMore: onLoadMore,
                        content: content
                    )
                }

            case .error(let error):
                errorContent(error)

            case .empty:
                emptyContent()
            }
        }
    }
}

// MARK: - End of List Indicator

struct NovaEndOfListView: View {
    var message: String = "没有更多内容了"

    var body: some View {
        VStack(spacing: 8) {
            Divider()
                .padding(.horizontal, 40)

            Text(message)
                .font(.system(size: 13))
                .foregroundColor(DesignColors.textSecondary)

            Image(systemName: "checkmark.circle")
                .font(.system(size: 20))
                .foregroundColor(DesignColors.textSecondary)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - List Separators

struct NovaSeparator: View {
    var color: Color = DesignColors.borderLight
    var height: CGFloat = 1

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: height)
    }
}

struct NovaSectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(DesignColors.textPrimary)

            Spacer()

            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DesignColors.brandPrimary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(DesignColors.surfaceLight)
    }
}

// MARK: - Preview

#if DEBUG
struct NovaList_Previews: PreviewProvider {
    struct PreviewItem: Identifiable {
        let id: String
        let title: String
        let subtitle: String
    }

    struct PreviewContainer: View {
        @State private var items: [PreviewItem] = (0..<10).map {
            PreviewItem(id: "\($0)", title: "项目 \($0)", subtitle: "描述 \($0)")
        }
        @State private var isLoadingMore = false
        @State private var hasMore = true

        var body: some View {
            NavigationView {
                VStack(spacing: 0) {
                    NovaSectionHeader(
                        title: "动态列表",
                        actionTitle: "查看全部",
                        action: {}
                    )

                    NovaEnhancedList(
                        items: items,
                        isLoadingMore: isLoadingMore,
                        hasMore: hasMore,
                        onRefresh: {
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            items = (0..<10).map {
                                PreviewItem(id: "\($0)", title: "项目 \($0)", subtitle: "已刷新")
                            }
                        },
                        onLoadMore: {
                            guard !isLoadingMore else { return }
                            isLoadingMore = true

                            try? await Task.sleep(nanoseconds: 1_500_000_000)

                            let currentCount = items.count
                            let newItems = (currentCount..<currentCount+5).map {
                                PreviewItem(id: "\($0)", title: "项目 \($0)", subtitle: "新加载")
                            }

                            items.append(contentsOf: newItems)

                            // Simulate no more after 30 items
                            if items.count >= 30 {
                                hasMore = false
                            }

                            isLoadingMore = false
                        },
                        content: { item in
                            VStack(spacing: 0) {
                                HStack(spacing: 12) {
                                    NovaAvatar(emoji: "📱", size: 44)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(DesignColors.textPrimary)

                                        Text(item.subtitle)
                                            .font(.system(size: 13))
                                            .foregroundColor(DesignColors.textSecondary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14))
                                        .foregroundColor(DesignColors.textSecondary)
                                }
                                .padding(16)

                                Divider()
                            }
                        }
                    )
                }
                .navigationTitle("")
                .navigationBarHidden(true)
            }
        }
    }

    static var previews: some View {
        PreviewContainer()
    }
}
#endif
