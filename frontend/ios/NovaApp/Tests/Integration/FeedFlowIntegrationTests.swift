import XCTest
@testable import NovaApp

/// Integration tests for feed functionality
@MainActor
class FeedFlowIntegrationTests: XCTestCase {
    var feedViewModel: FeedViewModel!
    var mockRepository: MockFeedRepository!

    override func setUp() {
        super.setUp()
        mockRepository = MockFeedRepository()
        feedViewModel = FeedViewModel(repository: mockRepository)
    }

    override func tearDown() {
        feedViewModel = nil
        mockRepository = nil
        super.tearDown()
    }

    // MARK: - Complete Feed Flow Tests

    func testCompleteFeedFlow_LoadInitialThenPaginate() async {
        // Given - Mock first page
        mockRepository.mockFeedResult = FeedResult(
            posts: Post.mockList(count: 20),
            hasMore: true
        )

        // When - Load initial
        await feedViewModel.loadInitial()

        // Then - Should have first page
        XCTAssertEqual(feedViewModel.posts.count, 20)
        XCTAssertTrue(feedViewModel.hasMore)
        XCTAssertFalse(feedViewModel.isLoading)

        // Given - Mock second page
        mockRepository.mockFeedResult = FeedResult(
            posts: Post.mockList(count: 20),
            hasMore: false
        )

        // When - Load more
        await feedViewModel.loadMore()

        // Then - Should have both pages
        XCTAssertEqual(feedViewModel.posts.count, 40)
        XCTAssertFalse(feedViewModel.hasMore)
    }

    func testFeedFlow_LoadAndLike() async {
        // Given - Feed with posts
        let posts = [
            Post.mock(id: "post_1", isLiked: false, likeCount: 10),
            Post.mock(id: "post_2", isLiked: false, likeCount: 5)
        ]
        mockRepository.mockFeedResult = FeedResult(posts: posts, hasMore: false)

        // When - Load feed
        await feedViewModel.loadInitial()
        XCTAssertEqual(feedViewModel.posts.count, 2)

        // When - Like first post
        await feedViewModel.toggleLike(postId: "post_1")

        // Then - Post should be liked
        XCTAssertTrue(feedViewModel.posts[0].isLiked)
        XCTAssertEqual(feedViewModel.posts[0].likeCount, 11)
        XCTAssertEqual(mockRepository.likePostCallCount, 1)
    }

    func testFeedFlow_LoadLikeUnlike() async {
        // Given
        let post = Post.mock(id: "post_1", isLiked: false, likeCount: 10)
        mockRepository.mockFeedResult = FeedResult(posts: [post], hasMore: false)

        // When - Load, like, then unlike
        await feedViewModel.loadInitial()
        await feedViewModel.toggleLike(postId: "post_1") // Like
        await feedViewModel.toggleLike(postId: "post_1") // Unlike

        // Then
        XCTAssertFalse(feedViewModel.posts[0].isLiked)
        XCTAssertEqual(feedViewModel.posts[0].likeCount, 10) // Back to original
        XCTAssertEqual(mockRepository.likePostCallCount, 1)
        XCTAssertEqual(mockRepository.unlikePostCallCount, 1)
    }

    func testFeedFlow_LoadAndDelete() async {
        // Given
        let posts = [
            Post.mock(id: "post_1"),
            Post.mock(id: "post_2"),
            Post.mock(id: "post_3")
        ]
        mockRepository.mockFeedResult = FeedResult(posts: posts, hasMore: false)

        // When - Load and delete middle post
        await feedViewModel.loadInitial()
        XCTAssertEqual(feedViewModel.posts.count, 3)

        await feedViewModel.deletePost(postId: "post_2")

        // Then
        XCTAssertEqual(feedViewModel.posts.count, 2)
        XCTAssertFalse(feedViewModel.posts.contains { $0.id == "post_2" })
        XCTAssertEqual(mockRepository.deletePostCallCount, 1)
    }

    func testFeedFlow_RefreshAfterChanges() async {
        // Given - Initial feed
        mockRepository.mockFeedResult = FeedResult(
            posts: Post.mockList(count: 5),
            hasMore: false
        )
        await feedViewModel.loadInitial()

        // When - Like some posts
        await feedViewModel.toggleLike(postId: feedViewModel.posts[0].id)
        await feedViewModel.toggleLike(postId: feedViewModel.posts[1].id)

        // When - Refresh feed
        mockRepository.mockFeedResult = FeedResult(
            posts: Post.mockList(count: 10), // New posts
            hasMore: true
        )
        await feedViewModel.refresh()

        // Then - Should have fresh data
        XCTAssertEqual(feedViewModel.posts.count, 10)
        XCTAssertTrue(feedViewModel.hasMore)
    }

    // MARK: - Pagination Flow Tests

    func testPaginationFlow_LoadThreePages() async {
        // Page 1
        mockRepository.mockFeedResult = FeedResult(
            posts: Post.mockList(count: 20),
            hasMore: true
        )
        await feedViewModel.loadInitial()
        XCTAssertEqual(feedViewModel.posts.count, 20)

        // Page 2
        mockRepository.mockFeedResult = FeedResult(
            posts: Post.mockList(count: 20),
            hasMore: true
        )
        await feedViewModel.loadMore()
        XCTAssertEqual(feedViewModel.posts.count, 40)

        // Page 3
        mockRepository.mockFeedResult = FeedResult(
            posts: Post.mockList(count: 15), // Last page with fewer items
            hasMore: false
        )
        await feedViewModel.loadMore()
        XCTAssertEqual(feedViewModel.posts.count, 55)
        XCTAssertFalse(feedViewModel.hasMore)
    }

    func testPaginationFlow_ReachEnd() async {
        // Given - Single page of data
        mockRepository.mockFeedResult = FeedResult(
            posts: Post.mockList(count: 10),
            hasMore: false
        )

        // When
        await feedViewModel.loadInitial()
        await feedViewModel.loadMore() // Should do nothing

        // Then - No additional load
        XCTAssertEqual(feedViewModel.posts.count, 10)
        XCTAssertEqual(mockRepository.fetchFeedCallCount, 1) // Only initial load
    }

    func testPaginationFlow_ErrorOnSecondPage() async {
        // Given - First page succeeds
        mockRepository.mockFeedResult = FeedResult(
            posts: Post.mockList(count: 20),
            hasMore: true
        )
        await feedViewModel.loadInitial()
        XCTAssertEqual(feedViewModel.posts.count, 20)

        // When - Second page fails
        mockRepository.mockError = APIError.networkError(NSError(domain: "test", code: -1))
        await feedViewModel.loadMore()

        // Then - Should keep first page data
        XCTAssertEqual(feedViewModel.posts.count, 20)
        XCTAssertNotNil(feedViewModel.error)
    }

    // MARK: - Error Handling Flow Tests

    func testErrorFlow_FailedLoadThenRetry() async {
        // Given - Initial load fails
        mockRepository.mockError = APIError.networkError(NSError(domain: "test", code: -1))
        await feedViewModel.loadInitial()

        // Then - Should be in error state
        XCTAssertTrue(feedViewModel.posts.isEmpty)
        XCTAssertNotNil(feedViewModel.error)

        // When - Retry (clear error and try again)
        mockRepository.mockError = nil
        mockRepository.mockFeedResult = FeedResult(
            posts: Post.mockList(count: 10),
            hasMore: false
        )
        await feedViewModel.refresh()

        // Then - Should succeed
        XCTAssertEqual(feedViewModel.posts.count, 10)
        XCTAssertNil(feedViewModel.error)
    }

    func testErrorFlow_LikeFailsAndReverts() async {
        // Given - Feed loaded
        let post = Post.mock(id: "post_1", isLiked: false, likeCount: 10)
        mockRepository.mockFeedResult = FeedResult(posts: [post], hasMore: false)
        await feedViewModel.loadInitial()

        // When - Like fails
        mockRepository.mockError = APIError.networkError(NSError(domain: "test", code: -1))
        await feedViewModel.toggleLike(postId: "post_1")

        // Then - Should revert to original state
        XCTAssertFalse(feedViewModel.posts[0].isLiked)
        XCTAssertEqual(feedViewModel.posts[0].likeCount, 10)
        XCTAssertNotNil(feedViewModel.error)
    }

    func testErrorFlow_DeleteFailsDoesNotRemove() async {
        // Given
        let posts = [
            Post.mock(id: "post_1"),
            Post.mock(id: "post_2")
        ]
        mockRepository.mockFeedResult = FeedResult(posts: posts, hasMore: false)
        await feedViewModel.loadInitial()

        // When - Delete fails
        mockRepository.mockError = APIError.serverError(500)
        await feedViewModel.deletePost(postId: "post_1")

        // Then - Post should still be there
        XCTAssertEqual(feedViewModel.posts.count, 2)
        XCTAssertNotNil(feedViewModel.error)
    }

    // MARK: - Optimistic Update Flow Tests

    func testOptimisticUpdate_ImmediateLikeResponse() async {
        // Given
        let post = Post.mock(id: "post_1", isLiked: false, likeCount: 10)
        mockRepository.mockFeedResult = FeedResult(posts: [post], hasMore: false)
        await feedViewModel.loadInitial()

        // When - Like (with slow network simulation)
        let likeTask = Task {
            await feedViewModel.toggleLike(postId: "post_1")
        }

        // Then - Should update immediately (optimistic)
        try? await Task.sleep(nanoseconds: 10_000_000) // 0.01s
        XCTAssertTrue(feedViewModel.posts[0].isLiked, "Should update optimistically")
        XCTAssertEqual(feedViewModel.posts[0].likeCount, 11)

        await likeTask.value
    }

    func testOptimisticUpdate_MultipleLikesOnDifferentPosts() async {
        // Given - Multiple posts
        let posts = [
            Post.mock(id: "post_1", isLiked: false, likeCount: 5),
            Post.mock(id: "post_2", isLiked: false, likeCount: 10),
            Post.mock(id: "post_3", isLiked: false, likeCount: 15)
        ]
        mockRepository.mockFeedResult = FeedResult(posts: posts, hasMore: false)
        await feedViewModel.loadInitial()

        // When - Like multiple posts
        await feedViewModel.toggleLike(postId: "post_1")
        await feedViewModel.toggleLike(postId: "post_3")

        // Then - Both should be liked
        XCTAssertTrue(feedViewModel.posts[0].isLiked)
        XCTAssertEqual(feedViewModel.posts[0].likeCount, 6)

        XCTAssertFalse(feedViewModel.posts[1].isLiked) // Unchanged
        XCTAssertEqual(feedViewModel.posts[1].likeCount, 10)

        XCTAssertTrue(feedViewModel.posts[2].isLiked)
        XCTAssertEqual(feedViewModel.posts[2].likeCount, 16)
    }

    // MARK: - Edge Case Tests

    func testEdgeCase_EmptyFeedLoad() async {
        // Given - Empty feed
        mockRepository.mockFeedResult = FeedResult(posts: [], hasMore: false)

        // When
        await feedViewModel.loadInitial()

        // Then
        XCTAssertTrue(feedViewModel.posts.isEmpty)
        XCTAssertFalse(feedViewModel.hasMore)
        XCTAssertNil(feedViewModel.error)
    }

    func testEdgeCase_SinglePostFeed() async {
        // Given
        mockRepository.mockFeedResult = FeedResult(
            posts: [Post.mock(id: "only_post")],
            hasMore: false
        )

        // When
        await feedViewModel.loadInitial()

        // Then
        XCTAssertEqual(feedViewModel.posts.count, 1)
        XCTAssertFalse(feedViewModel.hasMore)
    }

    func testEdgeCase_LikeNonExistentPost() async {
        // Given
        mockRepository.mockFeedResult = FeedResult(
            posts: [Post.mock(id: "post_1")],
            hasMore: false
        )
        await feedViewModel.loadInitial()

        // When - Try to like post that doesn't exist
        await feedViewModel.toggleLike(postId: "nonexistent")

        // Then - Should do nothing
        XCTAssertEqual(mockRepository.likePostCallCount, 0)
    }

    func testEdgeCase_DeleteNonExistentPost() async {
        // Given
        mockRepository.mockFeedResult = FeedResult(
            posts: [Post.mock(id: "post_1")],
            hasMore: false
        )
        await feedViewModel.loadInitial()

        // When - Delete non-existent post
        await feedViewModel.deletePost(postId: "nonexistent")

        // Then - Should still make API call (let server handle)
        XCTAssertEqual(mockRepository.deletePostCallCount, 1)
        XCTAssertEqual(feedViewModel.posts.count, 1) // Original post still there
    }

    // MARK: - Performance Tests

    func testPerformance_LoadLargeFeed() {
        // Given
        mockRepository.mockFeedResult = FeedResult(
            posts: Post.mockList(count: 100),
            hasMore: false
        )

        // When/Then - Should load within 0.5s
        measure {
            let expectation = XCTestExpectation(description: "Load complete")
            Task {
                await feedViewModel.loadInitial()
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 0.5)
        }
    }

    func testPerformance_MultipleLikes() {
        // Given
        mockRepository.mockFeedResult = FeedResult(
            posts: Post.mockList(count: 50),
            hasMore: false
        )

        // When/Then - Should complete within 1s
        measure {
            let expectation = XCTestExpectation(description: "Likes complete")
            Task {
                await feedViewModel.loadInitial()

                // Like 10 posts
                for i in 0..<10 {
                    await feedViewModel.toggleLike(postId: feedViewModel.posts[i].id)
                }

                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 1.0)
        }
    }

    // MARK: - Concurrent Operations

    func testConcurrent_SimultaneousLikesOnSamePost() async {
        // Given
        let post = Post.mock(id: "post_1", isLiked: false, likeCount: 10)
        mockRepository.mockFeedResult = FeedResult(posts: [post], hasMore: false)
        await feedViewModel.loadInitial()

        // When - Multiple simultaneous likes on same post
        async let like1 = feedViewModel.toggleLike(postId: "post_1")
        async let like2 = feedViewModel.toggleLike(postId: "post_1")
        async let like3 = feedViewModel.toggleLike(postId: "post_1")

        await like1
        await like2
        await like3

        // Then - Should be in a consistent state
        XCTAssertNotNil(feedViewModel.posts[0].isLiked)
        // Final state may vary, but should not crash
    }

    func testConcurrent_LoadAndLike() async {
        // Given
        mockRepository.mockFeedResult = FeedResult(
            posts: Post.mockList(count: 10),
            hasMore: false
        )

        // When - Load and like simultaneously
        async let load = feedViewModel.loadInitial()
        async let like = feedViewModel.toggleLike(postId: "post_1")

        await load
        await like

        // Then - Should handle gracefully
        XCTAssertFalse(feedViewModel.posts.isEmpty)
    }
}
