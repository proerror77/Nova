import Foundation
import SwiftUI

// MARK: - Home View Model

@MainActor
class HomeViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var selectedTab: HomeTab = .feed
    @Published var navigationState: HomeNavigationState?
    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Services

    private let contentService = ContentService()
    private let socialService = SocialService()

    // MARK: - Enums

    enum HomeTab {
        case feed
        case explore
        case trending
    }

    enum HomeNavigationState {
        case newPost
        case search
        case notification
        case report
        case thankYou
    }

    // MARK: - Pagination

    private var nextCursor: String?
    private var hasMore: Bool = true
    @Published var isLoadingMore = false

    // TODO: Get current user ID from authentication service
    private var currentUserId: String = "current_user_id"

    // MARK: - Lifecycle

    func loadFeed() async {
        isLoading = true
        errorMessage = nil
        nextCursor = nil
        hasMore = true

        do {
            switch selectedTab {
            case .feed:
                let response = try await socialService.getUserFeed(
                    userId: currentUserId,
                    limit: 20
                )
                posts = response.posts
                nextCursor = response.nextCursor
                hasMore = response.hasMore

            case .explore:
                let response = try await socialService.getExploreFeed(limit: 20)
                posts = response.posts
                nextCursor = response.nextCursor
                hasMore = response.hasMore

            case .trending:
                posts = try await socialService.getTrendingPosts(limit: 20)
                hasMore = false
            }
        } catch {
            errorMessage = "Failed to load feed: \(error.localizedDescription)"
            posts = []
        }

        isLoading = false
    }

    func loadMorePosts() async {
        guard hasMore, !isLoadingMore, let cursor = nextCursor else { return }

        isLoadingMore = true
        errorMessage = nil

        do {
            switch selectedTab {
            case .feed:
                let response = try await socialService.getUserFeed(
                    userId: currentUserId,
                    limit: 20,
                    cursor: cursor
                )
                posts.append(contentsOf: response.posts)
                nextCursor = response.nextCursor
                hasMore = response.hasMore

            case .explore:
                let response = try await socialService.getExploreFeed(
                    limit: 20,
                    cursor: cursor
                )
                posts.append(contentsOf: response.posts)
                nextCursor = response.nextCursor
                hasMore = response.hasMore

            case .trending:
                // Trending doesn't support pagination
                hasMore = false
            }
        } catch {
            errorMessage = "Failed to load more posts: \(error.localizedDescription)"
        }

        isLoadingMore = false
    }

    func refreshFeed() async {
        await loadFeed()
    }

    func selectTab(_ tab: HomeTab) {
        selectedTab = tab
        Task {
            await loadFeed()
        }
    }

    // MARK: - Actions

    func showNewPost() {
        navigationState = .newPost
    }

    func showSearch() {
        navigationState = .search
    }

    func showNotifications() {
        navigationState = .notification
    }

    func dismissNavigation() {
        navigationState = nil
    }
}
