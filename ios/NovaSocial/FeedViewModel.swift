import Foundation
import SwiftUI

/// ViewModel for managing the home feed
@MainActor
class FeedViewModel: ObservableObject {
    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasMore = true

    private var currentCursor: String?
    private let pageSize = 20

    // MARK: - Fetch Feed

    func loadFeed(refresh: Bool = false) async {
        // Prevent concurrent loads
        guard !isLoading else { return }

        // If refreshing, reset state
        if refresh {
            posts = []
            currentCursor = nil
            hasMore = true
        }

        // Don't load if no more posts
        guard hasMore else { return }

        isLoading = true
        errorMessage = nil

        do {
            struct FeedData: Codable {
                let feed: FeedResponse
            }

            let variables: [String: Any] = [
                "limit": pageSize,
                "cursor": currentCursor as Any
            ]

            let response = try await APIClient.shared.query(
                GraphQL.getFeed,
                variables: variables,
                responseType: FeedData.self
            )

            // Update state
            posts.append(contentsOf: response.feed.posts)
            currentCursor = response.feed.cursor
            hasMore = response.feed.hasMore

        } catch {
            errorMessage = error.localizedDescription
            print("❌ Feed load error: \(error)")
        }

        isLoading = false
    }

    // MARK: - Post Interactions

    func likePost(_ post: Post) async {
        do {
            struct LikeData: Codable {
                let likePost: Bool
            }

            let variables: [String: Any] = ["postId": post.id]

            _ = try await APIClient.shared.query(
                GraphQL.likePost,
                variables: variables,
                responseType: LikeData.self
            )

            // Update local state optimistically
            if let index = posts.firstIndex(where: { $0.id == post.id }) {
                posts[index].isLiked = true
                posts[index] = Post(
                    id: posts[index].id,
                    userId: posts[index].userId,
                    caption: posts[index].caption,
                    imageUrl: posts[index].imageUrl,
                    thumbnailUrl: posts[index].thumbnailUrl,
                    likeCount: posts[index].likeCount + 1,
                    commentCount: posts[index].commentCount,
                    viewCount: posts[index].viewCount,
                    createdAt: posts[index].createdAt,
                    author: posts[index].author,
                    isLiked: true
                )
            }

        } catch {
            errorMessage = "Failed to like post"
            print("❌ Like error: \(error)")
        }
    }

    func unlikePost(_ post: Post) async {
        do {
            struct UnlikeData: Codable {
                let unlikePost: Bool
            }

            let variables: [String: Any] = ["postId": post.id]

            _ = try await APIClient.shared.query(
                GraphQL.unlikePost,
                variables: variables,
                responseType: UnlikeData.self
            )

            // Update local state optimistically
            if let index = posts.firstIndex(where: { $0.id == post.id }) {
                posts[index].isLiked = false
                posts[index] = Post(
                    id: posts[index].id,
                    userId: posts[index].userId,
                    caption: posts[index].caption,
                    imageUrl: posts[index].imageUrl,
                    thumbnailUrl: posts[index].thumbnailUrl,
                    likeCount: max(0, posts[index].likeCount - 1),
                    commentCount: posts[index].commentCount,
                    viewCount: posts[index].viewCount,
                    createdAt: posts[index].createdAt,
                    author: posts[index].author,
                    isLiked: false
                )
            }

        } catch {
            errorMessage = "Failed to unlike post"
            print("❌ Unlike error: \(error)")
        }
    }

    // MARK: - Mock Data (Fallback when API unavailable)

    func loadMockData() {
        posts = [
            Post(
                id: "1",
                userId: "user1",
                caption: "kyleegigstead Cyborg dreams...",
                imageUrl: "post-image",
                thumbnailUrl: "post-image",
                likeCount: 142,
                commentCount: 23,
                viewCount: 1205,
                createdAt: Date().addingTimeInterval(-86400),
                author: User(
                    id: "user1",
                    username: "kyleegigstead",
                    displayName: "Simone Carter",
                    bio: nil,
                    avatarUrl: nil,
                    isVerified: false,
                    followerCount: 523,
                    followingCount: 342,
                    createdAt: Date()
                ),
                isLiked: false
            ),
            Post(
                id: "2",
                userId: "user2",
                caption: "Summer vibes ☀️",
                imageUrl: "post-image-2",
                thumbnailUrl: "post-image-2",
                likeCount: 89,
                commentCount: 12,
                viewCount: 654,
                createdAt: Date().addingTimeInterval(-172800),
                author: User(
                    id: "user2",
                    username: "summer_days",
                    displayName: "Simone Carter",
                    bio: nil,
                    avatarUrl: nil,
                    isVerified: true,
                    followerCount: 1234,
                    followingCount: 567,
                    createdAt: Date()
                ),
                isLiked: true
            ),
            Post(
                id: "3",
                userId: "user3",
                caption: "Nature therapy 🌿",
                imageUrl: "post-image-3",
                thumbnailUrl: "post-image-3",
                likeCount: 267,
                commentCount: 45,
                viewCount: 2103,
                createdAt: Date().addingTimeInterval(-259200),
                author: User(
                    id: "user3",
                    username: "nature_lover",
                    displayName: "Simone Carter",
                    bio: nil,
                    avatarUrl: nil,
                    isVerified: false,
                    followerCount: 892,
                    followingCount: 234,
                    createdAt: Date()
                ),
                isLiked: false
            )
        ]
    }
}
