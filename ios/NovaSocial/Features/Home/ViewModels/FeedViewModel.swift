import Foundation
import SwiftUI

// MARK: - Feed ViewModel

@MainActor
class FeedViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var posts: [FeedPost] = []
    @Published var postIds: [String] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var error: String?
    @Published var hasMore = true

    // MARK: - Private Properties

    private let feedService = FeedService()
    private var currentCursor: String?
    private var currentAlgorithm: FeedAlgorithm = .chronological

    // MARK: - Public Methods

    /// Load initial feed
    func loadFeed(algorithm: FeedAlgorithm = .chronological) async {
        guard !isLoading else { return }

        isLoading = true
        error = nil
        currentAlgorithm = algorithm
        currentCursor = nil

        do {
            let response = try await feedService.getFeed(algo: algorithm, limit: 20, cursor: nil)

            self.postIds = response.posts
            self.currentCursor = response.cursor
            self.hasMore = response.hasMore

            // For now, create mock posts from IDs until content-service integration
            self.posts = response.posts.enumerated().map { index, postId in
                createMockPost(id: postId, index: index)
            }

            self.error = nil
        } catch let apiError as APIError {
            self.error = apiError.localizedDescription
            print("Feed API Error: \(apiError)")
        } catch {
            self.error = "Failed to load feed: \(error.localizedDescription)"
            print("Feed Error: \(error)")
        }

        isLoading = false
    }

    /// Load more posts (pagination)
    func loadMore() async {
        guard !isLoadingMore, hasMore, let cursor = currentCursor else { return }

        isLoadingMore = true

        do {
            let response = try await feedService.getFeed(algo: currentAlgorithm, limit: 20, cursor: cursor)

            self.postIds.append(contentsOf: response.posts)
            self.currentCursor = response.cursor
            self.hasMore = response.hasMore

            // Append mock posts
            let newPosts = response.posts.enumerated().map { index, postId in
                createMockPost(id: postId, index: self.posts.count + index)
            }
            self.posts.append(contentsOf: newPosts)

        } catch {
            print("Load more error: \(error)")
        }

        isLoadingMore = false
    }

    /// Refresh feed (pull-to-refresh)
    func refresh() async {
        await loadFeed(algorithm: currentAlgorithm)
    }

    /// Switch feed algorithm
    func switchAlgorithm(to algorithm: FeedAlgorithm) async {
        guard algorithm != currentAlgorithm else { return }
        await loadFeed(algorithm: algorithm)
    }

    // MARK: - Private Methods

    /// Create mock post from ID until content-service integration is complete
    private func createMockPost(id: String, index: Int) -> FeedPost {
        let authors = ["Simone Carter", "Alex Johnson", "Maria Garcia", "James Wilson", "Emma Davis"]
        let contents = [
            "Cyborg dreams under the moonlit sky 🌙",
            "Just finished an amazing workout! 💪",
            "The sunset today was breathtaking ✨",
            "Working on something exciting! Stay tuned 🚀",
            "Coffee and code - the perfect combination ☕"
        ]

        return FeedPost(
            id: id,
            authorId: "user-\(index % 5)",
            authorName: authors[index % authors.count],
            authorAvatar: nil,
            content: contents[index % contents.count],
            mediaUrls: ["post-image", "post-image-2", "post-image-3"][index % 3...index % 3].map { $0 },
            createdAt: Date().addingTimeInterval(-Double(index * 3600)),
            likeCount: Int.random(in: 0...100),
            commentCount: Int.random(in: 0...50),
            shareCount: Int.random(in: 0...20),
            isLiked: false,
            isBookmarked: false
        )
    }
}

// MARK: - Feed State

enum FeedState {
    case idle
    case loading
    case loaded
    case error(String)
    case empty
}
