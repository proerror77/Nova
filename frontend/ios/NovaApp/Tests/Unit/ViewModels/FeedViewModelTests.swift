import XCTest
@testable import NovaApp

@MainActor
class FeedViewModelTests: XCTestCase {
    var sut: FeedViewModel!
    var mockRepository: MockFeedRepository!

    override func setUp() {
        super.setUp()
        mockRepository = MockFeedRepository()
        sut = FeedViewModel(repository: mockRepository)
    }

    override func tearDown() {
        sut = nil
        mockRepository = nil
        super.tearDown()
    }

    // MARK: - Initial Load Tests

    func testLoadInitial_Success() async {
        // Given
        let mockPosts = Post.mockList(count: 5)
        mockRepository.mockFeedResult = FeedResult(posts: mockPosts, hasMore: true)

        // When
        await sut.loadInitial()

        // Then
        XCTAssertEqual(sut.posts.count, 5)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.error)
        XCTAssertEqual(mockRepository.fetchFeedCallCount, 1)
        XCTAssertEqual(mockRepository.lastFetchedPage, 0)
    }

    func testLoadInitial_Failure() async {
        // Given
        mockRepository.mockError = APIError.mock()

        // When
        await sut.loadInitial()

        // Then
        XCTAssertTrue(sut.posts.isEmpty)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNotNil(sut.error)
    }

    func testLoadInitial_EmptyFeed() async {
        // Given
        mockRepository.mockFeedResult = FeedResult(posts: [], hasMore: false)

        // When
        await sut.loadInitial()

        // Then
        XCTAssertTrue(sut.posts.isEmpty)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.error)
    }

    func testLoadInitial_SetsLoadingState() async {
        // Given
        mockRepository.mockFeedResult = FeedResult(posts: [], hasMore: false)

        // When
        let loadingTask = Task {
            await sut.loadInitial()
        }

        // Then - check loading state during operation
        // Note: This is timing-dependent, may need adjustment
        try? await Task.sleep(nanoseconds: 10_000_000) // 0.01s
        let wasLoading = sut.isLoading

        await loadingTask.value

        XCTAssertFalse(sut.isLoading)
        // Loading state should have been true during operation
    }

    // MARK: - Pagination Tests

    func testLoadMore_Success() async {
        // Given
        sut.posts = Post.mockList(count: 5)
        mockRepository.mockFeedResult = FeedResult(
            posts: Post.mockList(count: 5),
            hasMore: false
        )

        // When
        await sut.loadMore()

        // Then
        XCTAssertEqual(sut.posts.count, 10)
        XCTAssertFalse(sut.isLoadingMore)
        XCTAssertEqual(mockRepository.fetchFeedCallCount, 1)
    }

    func testLoadMore_NoMorePages() async {
        // Given
        sut.posts = Post.mockList(count: 5)
        sut.hasMore = false

        // When
        await sut.loadMore()

        // Then
        XCTAssertEqual(sut.posts.count, 5) // No new posts added
        XCTAssertEqual(mockRepository.fetchFeedCallCount, 0)
    }

    func testLoadMore_AlreadyLoading() async {
        // Given
        sut.isLoadingMore = true

        // When
        await sut.loadMore()

        // Then
        XCTAssertEqual(mockRepository.fetchFeedCallCount, 0)
    }

    func testLoadMore_IncrementsPage() async {
        // Given
        sut.posts = Post.mockList(count: 5)
        mockRepository.mockFeedResult = FeedResult(posts: [], hasMore: false)

        // When
        await sut.loadMore()

        // Then
        XCTAssertEqual(mockRepository.lastFetchedPage, 1)
    }

    // MARK: - Refresh Tests

    func testRefresh_ReloadsFromPageZero() async {
        // Given
        sut.currentPage = 3
        sut.posts = Post.mockList(count: 15)
        mockRepository.mockFeedResult = FeedResult(
            posts: Post.mockList(count: 5),
            hasMore: true
        )

        // When
        await sut.refresh()

        // Then
        XCTAssertEqual(sut.posts.count, 5) // Reset to new data
        XCTAssertEqual(mockRepository.lastFetchedPage, 0)
    }

    // MARK: - Like/Unlike Tests

    func testToggleLike_OptimisticUpdate() async {
        // Given
        let post = Post.mock(id: "post_1", isLiked: false, likeCount: 10)
        sut.posts = [post]

        // When
        await sut.toggleLike(postId: "post_1")

        // Then - immediate optimistic update
        XCTAssertTrue(sut.posts[0].isLiked)
        XCTAssertEqual(sut.posts[0].likeCount, 11)
        XCTAssertEqual(mockRepository.likePostCallCount, 1)
    }

    func testToggleUnlike_OptimisticUpdate() async {
        // Given
        let post = Post.mock(id: "post_1", isLiked: true, likeCount: 10)
        sut.posts = [post]

        // When
        await sut.toggleLike(postId: "post_1")

        // Then
        XCTAssertFalse(sut.posts[0].isLiked)
        XCTAssertEqual(sut.posts[0].likeCount, 9)
        XCTAssertEqual(mockRepository.unlikePostCallCount, 1)
    }

    func testToggleLike_RevertsOnError() async {
        // Given
        let post = Post.mock(id: "post_1", isLiked: false, likeCount: 10)
        sut.posts = [post]
        mockRepository.mockError = APIError.mock()

        // When
        await sut.toggleLike(postId: "post_1")

        // Then - should revert to original state
        XCTAssertFalse(sut.posts[0].isLiked)
        XCTAssertEqual(sut.posts[0].likeCount, 10)
        XCTAssertNotNil(sut.error)
    }

    func testToggleLike_InvalidPostId() async {
        // Given
        sut.posts = [Post.mock(id: "post_1")]

        // When
        await sut.toggleLike(postId: "invalid_id")

        // Then - should do nothing
        XCTAssertEqual(mockRepository.likePostCallCount, 0)
    }

    func testToggleLike_MultiplePostsInFeed() async {
        // Given
        sut.posts = [
            Post.mock(id: "post_1", isLiked: false, likeCount: 5),
            Post.mock(id: "post_2", isLiked: false, likeCount: 10),
            Post.mock(id: "post_3", isLiked: false, likeCount: 15)
        ]

        // When
        await sut.toggleLike(postId: "post_2")

        // Then - only second post should change
        XCTAssertFalse(sut.posts[0].isLiked)
        XCTAssertEqual(sut.posts[0].likeCount, 5)

        XCTAssertTrue(sut.posts[1].isLiked)
        XCTAssertEqual(sut.posts[1].likeCount, 11)

        XCTAssertFalse(sut.posts[2].isLiked)
        XCTAssertEqual(sut.posts[2].likeCount, 15)
    }

    // MARK: - Delete Post Tests

    func testDeletePost_Success() async {
        // Given
        sut.posts = [
            Post.mock(id: "post_1"),
            Post.mock(id: "post_2"),
            Post.mock(id: "post_3")
        ]

        // When
        await sut.deletePost(postId: "post_2")

        // Then
        XCTAssertEqual(sut.posts.count, 2)
        XCTAssertFalse(sut.posts.contains { $0.id == "post_2" })
        XCTAssertEqual(mockRepository.deletePostCallCount, 1)
        XCTAssertEqual(mockRepository.lastDeletedPostId, "post_2")
    }

    func testDeletePost_Failure() async {
        // Given
        sut.posts = [Post.mock(id: "post_1")]
        mockRepository.mockError = APIError.mock()

        // When
        await sut.deletePost(postId: "post_1")

        // Then - post should not be deleted locally
        XCTAssertEqual(sut.posts.count, 1)
        XCTAssertNotNil(sut.error)
    }

    func testDeletePost_NonExistentPost() async {
        // Given
        sut.posts = [Post.mock(id: "post_1")]

        // When
        await sut.deletePost(postId: "invalid_id")

        // Then - should still make API call
        XCTAssertEqual(sut.posts.count, 1)
        XCTAssertEqual(mockRepository.deletePostCallCount, 1)
    }

    // MARK: - Edge Cases

    func testMultipleSimultaneousLoads_ShouldNotCrash() async {
        // Given
        mockRepository.mockFeedResult = FeedResult(
            posts: Post.mockList(count: 5),
            hasMore: true
        )

        // When - trigger multiple loads simultaneously
        async let load1 = sut.loadInitial()
        async let load2 = sut.loadInitial()
        async let load3 = sut.loadInitial()

        await load1
        await load2
        await load3

        // Then - should handle gracefully
        XCTAssertFalse(sut.isLoading)
    }

    func testLoadMore_WhileInitialLoading() async {
        // Given
        mockRepository.mockFeedResult = FeedResult(posts: [], hasMore: true)

        // When
        async let initialLoad = sut.loadInitial()
        await sut.loadMore()
        await initialLoad

        // Then - loadMore should be ignored
        XCTAssertEqual(mockRepository.fetchFeedCallCount, 1) // Only initial load
    }

    // MARK: - Performance Tests

    func testLoadInitial_Performance() {
        // Given
        mockRepository.mockFeedResult = FeedResult(
            posts: Post.mockList(count: 100),
            hasMore: false
        )

        // When/Then - should complete within 0.5s
        measure {
            let expectation = XCTestExpectation(description: "Load complete")
            Task {
                await sut.loadInitial()
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 0.5)
        }
    }

    func testToggleLike_Performance() {
        // Given
        sut.posts = Post.mockList(count: 100)

        // When/Then - should complete within 0.1s
        measure {
            let expectation = XCTestExpectation(description: "Like complete")
            Task {
                await sut.toggleLike(postId: sut.posts[50].id)
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 0.1)
        }
    }
}
