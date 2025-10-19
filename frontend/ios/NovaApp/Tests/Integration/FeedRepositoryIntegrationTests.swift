import XCTest
@testable import NovaApp

/// Integration tests for FeedRepository
/// Tests the integration between repository and API client
class FeedRepositoryIntegrationTests: XCTestCase {
    var sut: FeedRepository!
    var mockAPIClient: MockAPIClient!

    override func setUp() {
        super.setUp()
        mockAPIClient = MockAPIClient()
        sut = FeedRepository(apiClient: mockAPIClient)
    }

    override func tearDown() {
        sut = nil
        mockAPIClient = nil
        super.tearDown()
    }

    // MARK: - Fetch Feed Tests

    func testFetchFeed_Success() async throws {
        // Given
        let mockResponse = FeedAPIResponse(
            posts: [
                PostDTO.mock(id: "post_1"),
                PostDTO.mock(id: "post_2")
            ],
            pagination: PaginationDTO(hasMore: true, nextPage: 1)
        )
        mockAPIClient.mockResponse = mockResponse

        // When
        let result = try await sut.fetchFeed(page: 0, limit: 20)

        // Then
        XCTAssertEqual(result.posts.count, 2)
        XCTAssertTrue(result.hasMore)
        XCTAssertEqual(mockAPIClient.lastRequest?.path, "/api/v1/feed")
        XCTAssertEqual(mockAPIClient.lastRequest?.method, .get)
        XCTAssertEqual(mockAPIClient.lastRequest?.queryParameters?["page"] as? Int, 0)
        XCTAssertEqual(mockAPIClient.lastRequest?.queryParameters?["limit"] as? Int, 20)
    }

    func testFetchFeed_NetworkError() async {
        // Given
        mockAPIClient.mockError = NetworkError.noConnection

        // When/Then
        do {
            _ = try await sut.fetchFeed(page: 0, limit: 20)
            XCTFail("Should have thrown an error")
        } catch {
            XCTAssertTrue(error is NetworkError)
        }
    }

    func testFetchFeed_InvalidResponse() async {
        // Given
        mockAPIClient.mockResponse = "invalid_data"

        // When/Then
        do {
            _ = try await sut.fetchFeed(page: 0, limit: 20)
            XCTFail("Should have thrown an error")
        } catch {
            XCTAssertTrue(error is APIError)
        }
    }

    func testFetchFeed_EmptyResponse() async throws {
        // Given
        let emptyResponse = FeedAPIResponse(
            posts: [],
            pagination: PaginationDTO(hasMore: false, nextPage: nil)
        )
        mockAPIClient.mockResponse = emptyResponse

        // When
        let result = try await sut.fetchFeed(page: 0, limit: 20)

        // Then
        XCTAssertTrue(result.posts.isEmpty)
        XCTAssertFalse(result.hasMore)
    }

    // MARK: - Like Post Tests

    func testLikePost_Success() async throws {
        // Given
        let postId = "post_123"
        mockAPIClient.mockResponse = ["success": true]

        // When
        try await sut.likePost(postId: postId)

        // Then
        XCTAssertEqual(mockAPIClient.lastRequest?.path, "/api/v1/posts/\(postId)/like")
        XCTAssertEqual(mockAPIClient.lastRequest?.method, .post)
        XCTAssertEqual(mockAPIClient.requestCallCount, 1)
    }

    func testLikePost_AlreadyLiked() async {
        // Given
        let postId = "post_123"
        mockAPIClient.mockError = APIError.mock(code: "ALREADY_LIKED", statusCode: 409)

        // When/Then
        do {
            try await sut.likePost(postId: postId)
            XCTFail("Should have thrown an error")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "ALREADY_LIKED")
            XCTAssertEqual(error.statusCode, 409)
        } catch {
            XCTFail("Wrong error type")
        }
    }

    func testLikePost_Unauthorized() async {
        // Given
        mockAPIClient.mockError = APIError.mock(code: "UNAUTHORIZED", statusCode: 401)

        // When/Then
        do {
            try await sut.likePost(postId: "post_123")
            XCTFail("Should have thrown an error")
        } catch let error as APIError {
            XCTAssertEqual(error.statusCode, 401)
        } catch {
            XCTFail("Wrong error type")
        }
    }

    // MARK: - Unlike Post Tests

    func testUnlikePost_Success() async throws {
        // Given
        let postId = "post_123"
        mockAPIClient.mockResponse = ["success": true]

        // When
        try await sut.unlikePost(postId: postId)

        // Then
        XCTAssertEqual(mockAPIClient.lastRequest?.path, "/api/v1/posts/\(postId)/unlike")
        XCTAssertEqual(mockAPIClient.lastRequest?.method, .delete)
    }

    func testUnlikePost_NotLiked() async {
        // Given
        mockAPIClient.mockError = APIError.mock(code: "NOT_LIKED", statusCode: 409)

        // When/Then
        do {
            try await sut.unlikePost(postId: "post_123")
            XCTFail("Should have thrown an error")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "NOT_LIKED")
        } catch {
            XCTFail("Wrong error type")
        }
    }

    // MARK: - Delete Post Tests

    func testDeletePost_Success() async throws {
        // Given
        let postId = "post_123"
        mockAPIClient.mockResponse = ["success": true]

        // When
        try await sut.deletePost(postId: postId)

        // Then
        XCTAssertEqual(mockAPIClient.lastRequest?.path, "/api/v1/posts/\(postId)")
        XCTAssertEqual(mockAPIClient.lastRequest?.method, .delete)
    }

    func testDeletePost_NotFound() async {
        // Given
        mockAPIClient.mockError = APIError.mock(code: "NOT_FOUND", statusCode: 404)

        // When/Then
        do {
            try await sut.deletePost(postId: "invalid_id")
            XCTFail("Should have thrown an error")
        } catch let error as APIError {
            XCTAssertEqual(error.statusCode, 404)
        } catch {
            XCTFail("Wrong error type")
        }
    }

    func testDeletePost_Forbidden() async {
        // Given - trying to delete someone else's post
        mockAPIClient.mockError = APIError.mock(code: "FORBIDDEN", statusCode: 403)

        // When/Then
        do {
            try await sut.deletePost(postId: "post_123")
            XCTFail("Should have thrown an error")
        } catch let error as APIError {
            XCTAssertEqual(error.statusCode, 403)
        } catch {
            XCTFail("Wrong error type")
        }
    }

    // MARK: - Caching Tests

    func testFetchFeed_UsesCacheWhenAvailable() async throws {
        // Given
        let cachedPosts = Post.mockList(count: 5)
        let cache = MockFeedCache()
        cache.cachedFeed = cachedPosts
        sut = FeedRepository(apiClient: mockAPIClient, cache: cache)

        // When
        let result = try await sut.fetchFeed(page: 0, limit: 20, useCache: true)

        // Then
        XCTAssertEqual(result.posts.count, 5)
        XCTAssertEqual(mockAPIClient.requestCallCount, 0) // No API call made
    }

    func testFetchFeed_FetchesFromAPIWhenCacheExpired() async throws {
        // Given
        let cache = MockFeedCache()
        cache.isExpired = true
        sut = FeedRepository(apiClient: mockAPIClient, cache: cache)

        let mockResponse = FeedAPIResponse(
            posts: [PostDTO.mock()],
            pagination: PaginationDTO(hasMore: false, nextPage: nil)
        )
        mockAPIClient.mockResponse = mockResponse

        // When
        let result = try await sut.fetchFeed(page: 0, limit: 20, useCache: true)

        // Then
        XCTAssertEqual(mockAPIClient.requestCallCount, 1) // API call made
        XCTAssertTrue(cache.didUpdateCache) // Cache was updated
    }

    // MARK: - Retry Logic Tests

    func testFetchFeed_RetriesOnNetworkFailure() async throws {
        // Given
        mockAPIClient.failureCount = 2 // Fail first 2 attempts, succeed on 3rd
        let mockResponse = FeedAPIResponse(
            posts: [PostDTO.mock()],
            pagination: PaginationDTO(hasMore: false, nextPage: nil)
        )
        mockAPIClient.mockResponse = mockResponse

        // When
        let result = try await sut.fetchFeed(page: 0, limit: 20)

        // Then
        XCTAssertEqual(result.posts.count, 1)
        XCTAssertEqual(mockAPIClient.requestCallCount, 3) // 2 failures + 1 success
    }

    func testFetchFeed_FailsAfterMaxRetries() async {
        // Given
        mockAPIClient.failureCount = 10 // Fail all attempts
        mockAPIClient.mockError = NetworkError.timeout

        // When/Then
        do {
            _ = try await sut.fetchFeed(page: 0, limit: 20)
            XCTFail("Should have thrown an error")
        } catch {
            XCTAssertEqual(mockAPIClient.requestCallCount, 3) // Max retries = 3
        }
    }

    // MARK: - Pagination Tests

    func testFetchFeed_MultiplePagesSequentially() async throws {
        // Given
        let page1Response = FeedAPIResponse(
            posts: Post.mockList(count: 20).map { PostDTO(from: $0) },
            pagination: PaginationDTO(hasMore: true, nextPage: 1)
        )
        let page2Response = FeedAPIResponse(
            posts: Post.mockList(count: 20).map { PostDTO(from: $0) },
            pagination: PaginationDTO(hasMore: true, nextPage: 2)
        )

        // When - Fetch page 0
        mockAPIClient.mockResponse = page1Response
        let result1 = try await sut.fetchFeed(page: 0, limit: 20)

        // Then
        XCTAssertEqual(result1.posts.count, 20)
        XCTAssertTrue(result1.hasMore)

        // When - Fetch page 1
        mockAPIClient.mockResponse = page2Response
        let result2 = try await sut.fetchFeed(page: 1, limit: 20)

        // Then
        XCTAssertEqual(result2.posts.count, 20)
        XCTAssertTrue(result2.hasMore)
    }

    // MARK: - Performance Tests

    func testFetchFeed_Performance() async throws {
        // Given
        let largeFeedResponse = FeedAPIResponse(
            posts: Post.mockList(count: 100).map { PostDTO(from: $0) },
            pagination: PaginationDTO(hasMore: true, nextPage: 1)
        )
        mockAPIClient.mockResponse = largeFeedResponse

        // When/Then - Should complete within 1 second
        let elapsed = try await PerformanceTestHelper.measureAsync {
            _ = try await sut.fetchFeed(page: 0, limit: 100)
        }

        XCTAssertLessThan(elapsed, 1.0, "Feed fetch took \(elapsed)s, expected < 1s")
    }
}

// MARK: - Mock Feed Cache

class MockFeedCache {
    var cachedFeed: [Post]?
    var isExpired = false
    var didUpdateCache = false

    func get() -> [Post]? {
        guard !isExpired else { return nil }
        return cachedFeed
    }

    func set(_ posts: [Post]) {
        cachedFeed = posts
        didUpdateCache = true
    }

    func clear() {
        cachedFeed = nil
    }
}

// MARK: - Network Error

enum NetworkError: Error {
    case noConnection
    case timeout
}

// MARK: - DTOs

struct FeedAPIResponse: Codable {
    let posts: [PostDTO]
    let pagination: PaginationDTO
}

struct PostDTO: Codable {
    let id: String
    let authorId: String
    let imageURL: String?
    let caption: String
    let likeCount: Int
    let commentCount: Int
    let createdAt: String

    static func mock(
        id: String = "post_123",
        authorId: String = "user_123",
        caption: String = "Test post"
    ) -> PostDTO {
        return PostDTO(
            id: id,
            authorId: authorId,
            imageURL: "https://picsum.photos/400/600",
            caption: caption,
            likeCount: 0,
            commentCount: 0,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    init(from post: Post) {
        self.id = post.id
        self.authorId = post.author.id
        self.imageURL = post.imageURL?.absoluteString
        self.caption = post.caption
        self.likeCount = post.likeCount
        self.commentCount = post.commentCount
        self.createdAt = ISO8601DateFormatter().string(from: post.createdAt)
    }
}

struct PaginationDTO: Codable {
    let hasMore: Bool
    let nextPage: Int?
}
