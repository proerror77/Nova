import Foundation
@testable import NovaApp

/// Mock Feed Repository for unit testing
class MockFeedRepository: FeedRepository {
    // MARK: - Mock Data
    var mockFeedResult: FeedResult?
    var mockError: Error?
    var fetchFeedCallCount = 0
    var likePostCallCount = 0
    var unlikePostCallCount = 0
    var deletePostCallCount = 0

    // MARK: - Recorded Calls
    var lastFetchedPage: Int?
    var lastFetchedLimit: Int?
    var lastLikedPostId: String?
    var lastUnlikedPostId: String?
    var lastDeletedPostId: String?

    // MARK: - Mock Responses
    override func fetchFeed(page: Int, limit: Int) async throws -> FeedResult {
        fetchFeedCallCount += 1
        lastFetchedPage = page
        lastFetchedLimit = limit

        if let error = mockError {
            throw error
        }

        if let result = mockFeedResult {
            return result
        }

        // Default mock response
        return FeedResult(
            posts: Post.mockList(count: limit),
            hasMore: page < 2
        )
    }

    override func likePost(postId: String) async throws {
        likePostCallCount += 1
        lastLikedPostId = postId

        if let error = mockError {
            throw error
        }
    }

    override func unlikePost(postId: String) async throws {
        unlikePostCallCount += 1
        lastUnlikedPostId = postId

        if let error = mockError {
            throw error
        }
    }

    override func deletePost(postId: String) async throws {
        deletePostCallCount += 1
        lastDeletedPostId = postId

        if let error = mockError {
            throw error
        }
    }

    // MARK: - Reset
    func reset() {
        mockFeedResult = nil
        mockError = nil
        fetchFeedCallCount = 0
        likePostCallCount = 0
        unlikePostCallCount = 0
        deletePostCallCount = 0
        lastFetchedPage = nil
        lastFetchedLimit = nil
        lastLikedPostId = nil
        lastUnlikedPostId = nil
        lastDeletedPostId = nil
    }
}
