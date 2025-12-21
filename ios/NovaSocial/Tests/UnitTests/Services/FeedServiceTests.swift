import XCTest
@testable import ICERED

/// Unit tests for FeedService and Feed models
/// Tests JSON parsing, bookmark count handling, and feed post transformations
final class FeedServiceTests: XCTestCase {

    // MARK: - FeedPostRaw JSON Parsing Tests

    /// Test that FeedPostRaw correctly parses bookmark_count from API response
    func testFeedPostRawParsesBookmarkCount() throws {
        let json = """
        {
            "id": "post-123",
            "user_id": "user-456",
            "content": "Test post content",
            "created_at": 1703116800,
            "ranking_score": 0.85,
            "like_count": 10,
            "comment_count": 5,
            "share_count": 2,
            "bookmark_count": 7,
            "media_urls": ["https://example.com/image.jpg"],
            "media_type": "image",
            "author_username": "testuser",
            "author_display_name": "Test User",
            "author_avatar": "https://example.com/avatar.jpg"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let feedPostRaw = try decoder.decode(FeedPostRaw.self, from: json)

        XCTAssertEqual(feedPostRaw.id, "post-123")
        XCTAssertEqual(feedPostRaw.userId, "user-456")
        XCTAssertEqual(feedPostRaw.bookmarkCount, 7, "bookmarkCount should be parsed from API")
        XCTAssertEqual(feedPostRaw.likeCount, 10)
        XCTAssertEqual(feedPostRaw.commentCount, 5)
        XCTAssertEqual(feedPostRaw.shareCount, 2)
    }

    /// Test that FeedPostRaw handles missing bookmark_count (nil)
    func testFeedPostRawHandlesMissingBookmarkCount() throws {
        let json = """
        {
            "id": "post-123",
            "user_id": "user-456",
            "content": "Test post content",
            "created_at": 1703116800,
            "ranking_score": 0.85,
            "like_count": 10,
            "comment_count": 5,
            "share_count": 2,
            "media_urls": [],
            "media_type": null
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let feedPostRaw = try decoder.decode(FeedPostRaw.self, from: json)

        XCTAssertNil(feedPostRaw.bookmarkCount, "bookmarkCount should be nil when not present in API response")
    }

    /// Test that FeedPostRaw handles zero bookmark_count
    func testFeedPostRawHandlesZeroBookmarkCount() throws {
        let json = """
        {
            "id": "post-123",
            "user_id": "user-456",
            "content": "Test post content",
            "created_at": 1703116800,
            "ranking_score": 0.85,
            "like_count": 0,
            "comment_count": 0,
            "share_count": 0,
            "bookmark_count": 0,
            "media_urls": [],
            "media_type": null
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let feedPostRaw = try decoder.decode(FeedPostRaw.self, from: json)

        XCTAssertEqual(feedPostRaw.bookmarkCount, 0, "bookmarkCount should be 0 when explicitly set to 0")
    }

    // MARK: - FeedPost Transformation Tests

    /// Test that FeedPost correctly transforms bookmarkCount from FeedPostRaw
    func testFeedPostTransformsBookmarkCount() throws {
        let json = """
        {
            "id": "post-123",
            "user_id": "user-456",
            "content": "Test post content",
            "created_at": 1703116800,
            "ranking_score": 0.85,
            "like_count": 10,
            "comment_count": 5,
            "share_count": 2,
            "bookmark_count": 15,
            "media_urls": ["https://example.com/image.jpg"],
            "media_type": "image",
            "author_username": "testuser",
            "author_display_name": "Test User",
            "author_avatar": "https://example.com/avatar.jpg"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let feedPostRaw = try decoder.decode(FeedPostRaw.self, from: json)
        let feedPost = FeedPost(from: feedPostRaw)

        XCTAssertEqual(feedPost.bookmarkCount, 15, "FeedPost should have bookmarkCount from raw data")
        XCTAssertEqual(feedPost.likeCount, 10)
        XCTAssertEqual(feedPost.commentCount, 5)
        XCTAssertEqual(feedPost.shareCount, 2)
    }

    /// Test that FeedPost defaults bookmarkCount to 0 when raw data has nil
    func testFeedPostDefaultsBookmarkCountToZero() throws {
        let json = """
        {
            "id": "post-123",
            "user_id": "user-456",
            "content": "Test post content",
            "created_at": 1703116800,
            "ranking_score": 0.85,
            "like_count": 10,
            "comment_count": 5,
            "share_count": 2,
            "media_urls": [],
            "media_type": null
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let feedPostRaw = try decoder.decode(FeedPostRaw.self, from: json)
        let feedPost = FeedPost(from: feedPostRaw)

        XCTAssertEqual(feedPost.bookmarkCount, 0, "FeedPost should default bookmarkCount to 0 when nil")
    }

    // MARK: - FeedResponse Parsing Tests

    /// Test parsing complete feed response with multiple posts
    func testFeedResponseParsing() throws {
        let json = """
        {
            "posts": [
                {
                    "id": "post-1",
                    "user_id": "user-1",
                    "content": "First post",
                    "created_at": 1703116800,
                    "ranking_score": 0.9,
                    "like_count": 100,
                    "comment_count": 10,
                    "share_count": 5,
                    "bookmark_count": 20,
                    "media_urls": [],
                    "media_type": null
                },
                {
                    "id": "post-2",
                    "user_id": "user-2",
                    "content": "Second post",
                    "created_at": 1703116900,
                    "ranking_score": 0.8,
                    "like_count": 50,
                    "comment_count": 5,
                    "share_count": 2,
                    "bookmark_count": 8,
                    "media_urls": ["https://example.com/img.jpg"],
                    "media_type": "image"
                }
            ],
            "next_cursor": "cursor-abc123",
            "has_more": true
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let response = try decoder.decode(FeedResponse.self, from: json)

        XCTAssertEqual(response.posts.count, 2)
        XCTAssertEqual(response.posts[0].bookmarkCount, 20)
        XCTAssertEqual(response.posts[1].bookmarkCount, 8)
        XCTAssertEqual(response.nextCursor, "cursor-abc123")
        XCTAssertTrue(response.hasMore)
    }

    /// Test parsing feed response with empty posts array
    func testFeedResponseEmptyPosts() throws {
        let json = """
        {
            "posts": [],
            "next_cursor": null,
            "has_more": false
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let response = try decoder.decode(FeedResponse.self, from: json)

        XCTAssertTrue(response.posts.isEmpty)
        XCTAssertNil(response.nextCursor)
        XCTAssertFalse(response.hasMore)
    }

    // MARK: - Post Model Tests

    /// Test Post model parses bookmarkCount
    func testPostModelParsesBookmarkCount() throws {
        let json = """
        {
            "id": "post-123",
            "author_id": "user-456",
            "content": "Test content",
            "created_at": 1703116800,
            "updated_at": 1703116800,
            "status": "published",
            "media_urls": [],
            "media_type": null,
            "like_count": 10,
            "comment_count": 5,
            "share_count": 2,
            "bookmark_count": 3
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let post = try decoder.decode(Post.self, from: json)

        XCTAssertEqual(post.id, "post-123")
        XCTAssertEqual(post.bookmarkCount, 3, "Post should parse bookmarkCount from JSON")
        XCTAssertEqual(post.likeCount, 10)
    }

    /// Test Post model handles missing bookmarkCount
    func testPostModelHandlesMissingBookmarkCount() throws {
        let json = """
        {
            "id": "post-123",
            "author_id": "user-456",
            "content": "Test content",
            "created_at": 1703116800,
            "updated_at": 1703116800,
            "status": "published",
            "media_urls": [],
            "media_type": null,
            "like_count": 10,
            "comment_count": 5,
            "share_count": 2
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let post = try decoder.decode(Post.self, from: json)

        XCTAssertNil(post.bookmarkCount, "Post bookmarkCount should be nil when not in JSON")
    }

    // MARK: - Author Information Tests

    /// Test that FeedPostRaw correctly parses author information
    func testFeedPostRawAuthorInformationParsing() throws {
        let json = """
        {
            "id": "post-123",
            "user_id": "user-456",
            "content": "Test post",
            "created_at": 1703116800,
            "ranking_score": 0.85,
            "like_count": 10,
            "comment_count": 5,
            "share_count": 2,
            "bookmark_count": 7,
            "media_urls": [],
            "media_type": null,
            "author_username": "johndoe",
            "author_display_name": "John Doe",
            "author_avatar": "https://example.com/avatar.jpg"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let feedPostRaw = try decoder.decode(FeedPostRaw.self, from: json)

        // Test FeedPostRaw has all author fields
        XCTAssertEqual(feedPostRaw.authorUsername, "johndoe")
        XCTAssertEqual(feedPostRaw.authorDisplayName, "John Doe")
        XCTAssertEqual(feedPostRaw.authorAvatar, "https://example.com/avatar.jpg")
    }

    /// Test that FeedPost derives authorName from display name (priority: displayName > username)
    func testFeedPostAuthorNameFromDisplayName() throws {
        let json = """
        {
            "id": "post-123",
            "user_id": "user-456",
            "content": "Test post",
            "created_at": 1703116800,
            "ranking_score": 0.85,
            "like_count": 10,
            "comment_count": 5,
            "share_count": 2,
            "bookmark_count": 7,
            "media_urls": [],
            "media_type": null,
            "author_username": "johndoe",
            "author_display_name": "John Doe",
            "author_avatar": "https://example.com/avatar.jpg"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let feedPostRaw = try decoder.decode(FeedPostRaw.self, from: json)
        let feedPost = FeedPost(from: feedPostRaw)

        // FeedPost should use authorDisplayName for authorName (priority: displayName > username)
        XCTAssertEqual(feedPost.authorName, "John Doe", "authorName should use display name when available")
        XCTAssertEqual(feedPost.authorAvatar, "https://example.com/avatar.jpg")
    }

    /// Test that FeedPost falls back to username when display name is missing
    func testFeedPostAuthorNameFromUsername() throws {
        let json = """
        {
            "id": "post-123",
            "user_id": "user-456",
            "content": "Test post",
            "created_at": 1703116800,
            "ranking_score": 0.85,
            "like_count": 10,
            "comment_count": 5,
            "share_count": 2,
            "bookmark_count": 7,
            "media_urls": [],
            "media_type": null,
            "author_username": "johndoe",
            "author_avatar": "https://example.com/avatar.jpg"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let feedPostRaw = try decoder.decode(FeedPostRaw.self, from: json)
        let feedPost = FeedPost(from: feedPostRaw)

        // FeedPost should fall back to username when displayName is nil
        XCTAssertEqual(feedPost.authorName, "johndoe", "authorName should fall back to username")
    }

    /// Test that missing author information defaults to placeholder
    func testMissingAuthorInformation() throws {
        let json = """
        {
            "id": "post-123",
            "user_id": "user-456",
            "content": "Test post",
            "created_at": 1703116800,
            "ranking_score": 0.85,
            "like_count": 10,
            "comment_count": 5,
            "share_count": 2,
            "bookmark_count": 7,
            "media_urls": [],
            "media_type": null
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let feedPostRaw = try decoder.decode(FeedPostRaw.self, from: json)
        let feedPost = FeedPost(from: feedPostRaw)

        // FeedPostRaw should have nil author fields
        XCTAssertNil(feedPostRaw.authorUsername)
        XCTAssertNil(feedPostRaw.authorDisplayName)
        XCTAssertNil(feedPostRaw.authorAvatar)

        // FeedPost should use placeholder when all author info is missing
        XCTAssertTrue(feedPost.authorName.hasPrefix("User "), "authorName should be placeholder when missing")
        XCTAssertNil(feedPost.authorAvatar)
    }
}
