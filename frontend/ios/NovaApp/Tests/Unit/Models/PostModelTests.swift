import XCTest
@testable import NovaApp

class PostModelTests: XCTestCase {

    // MARK: - Codable Tests

    func testDecode_ValidJSON() throws {
        // Given
        let json = """
        {
            "id": "post_123",
            "author": {
                "id": "user_456",
                "username": "johndoe",
                "display_name": "John Doe",
                "avatar_url": null,
                "bio": null,
                "followers_count": 100,
                "following_count": 50,
                "posts_count": 25
            },
            "image_url": "https://example.com/image.jpg",
            "caption": "Beautiful sunset",
            "like_count": 42,
            "comment_count": 7,
            "is_liked": true,
            "created_at": "2025-10-18T10:30:00Z"
        }
        """
        let data = json.data(using: .utf8)!

        // When
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let post = try decoder.decode(Post.self, from: data)

        // Then
        XCTAssertEqual(post.id, "post_123")
        XCTAssertEqual(post.author.id, "user_456")
        XCTAssertEqual(post.author.username, "johndoe")
        XCTAssertEqual(post.author.displayName, "John Doe")
        XCTAssertEqual(post.imageURL?.absoluteString, "https://example.com/image.jpg")
        XCTAssertEqual(post.caption, "Beautiful sunset")
        XCTAssertEqual(post.likeCount, 42)
        XCTAssertEqual(post.commentCount, 7)
        XCTAssertTrue(post.isLiked)
    }

    func testDecode_MinimalJSON() throws {
        // Given - minimal required fields
        let json = """
        {
            "id": "post_1",
            "author": {
                "id": "user_1",
                "username": "user",
                "display_name": "User"
            },
            "image_url": null,
            "caption": null,
            "like_count": 0,
            "comment_count": 0,
            "is_liked": false,
            "created_at": "2025-10-18T00:00:00Z"
        }
        """
        let data = json.data(using: .utf8)!

        // When
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let post = try decoder.decode(Post.self, from: data)

        // Then
        XCTAssertNotNil(post)
        XCTAssertNil(post.imageURL)
        XCTAssertNil(post.caption)
        XCTAssertEqual(post.likeCount, 0)
        XCTAssertEqual(post.commentCount, 0)
    }

    func testEncode_ValidPost() throws {
        // Given
        let post = Post.mock(
            id: "post_1",
            likeCount: 10,
            commentCount: 5,
            isLiked: true
        )

        // When
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(post)
        let jsonString = String(data: data, encoding: .utf8)!

        // Then
        XCTAssertTrue(jsonString.contains("\"id\":\"post_1\""))
        XCTAssertTrue(jsonString.contains("\"like_count\":10"))
        XCTAssertTrue(jsonString.contains("\"comment_count\":5"))
        XCTAssertTrue(jsonString.contains("\"is_liked\":true"))
    }

    func testDecode_MissingRequiredField() {
        // Given - missing 'id' field
        let json = """
        {
            "author": {"id": "user_1", "username": "user", "display_name": "User"},
            "like_count": 0,
            "comment_count": 0,
            "is_liked": false,
            "created_at": "2025-10-18T00:00:00Z"
        }
        """
        let data = json.data(using: .utf8)!

        // When/Then
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertThrowsError(try decoder.decode(Post.self, from: data))
    }

    // MARK: - Equatable Tests

    func testEquality_SamePosts() {
        // Given
        let post1 = Post.mock(id: "post_1", likeCount: 10, isLiked: false)
        let post2 = Post.mock(id: "post_1", likeCount: 10, isLiked: false)

        // When/Then
        XCTAssertEqual(post1, post2)
    }

    func testEquality_DifferentLikeCount() {
        // Given
        let post1 = Post.mock(id: "post_1", likeCount: 10)
        let post2 = Post.mock(id: "post_1", likeCount: 11)

        // When/Then
        XCTAssertNotEqual(post1, post2)
    }

    func testEquality_DifferentLikedState() {
        // Given
        let post1 = Post.mock(id: "post_1", isLiked: false)
        let post2 = Post.mock(id: "post_1", isLiked: true)

        // When/Then
        XCTAssertNotEqual(post1, post2)
    }

    func testEquality_DifferentId() {
        // Given
        let post1 = Post.mock(id: "post_1")
        let post2 = Post.mock(id: "post_2")

        // When/Then
        XCTAssertNotEqual(post1, post2)
    }

    // MARK: - Hashable Tests

    func testHashable_SamePosts() {
        // Given
        let post1 = Post.mock(id: "post_1")
        let post2 = Post.mock(id: "post_1")

        // When
        let set: Set<Post> = [post1, post2]

        // Then - should only contain one element
        XCTAssertEqual(set.count, 1)
    }

    func testHashable_DifferentPosts() {
        // Given
        let post1 = Post.mock(id: "post_1")
        let post2 = Post.mock(id: "post_2")

        // When
        let set: Set<Post> = [post1, post2]

        // Then
        XCTAssertEqual(set.count, 2)
    }
}

// MARK: - User Model Tests

class UserModelTests: XCTestCase {

    func testDecode_ValidJSON() throws {
        // Given
        let json = """
        {
            "id": "user_123",
            "username": "johndoe",
            "display_name": "John Doe",
            "avatar_url": "https://example.com/avatar.jpg",
            "bio": "Software developer",
            "followers_count": 1000,
            "following_count": 500,
            "posts_count": 250
        }
        """
        let data = json.data(using: .utf8)!

        // When
        let user = try JSONDecoder().decode(User.self, from: data)

        // Then
        XCTAssertEqual(user.id, "user_123")
        XCTAssertEqual(user.username, "johndoe")
        XCTAssertEqual(user.displayName, "John Doe")
        XCTAssertEqual(user.avatarURL?.absoluteString, "https://example.com/avatar.jpg")
        XCTAssertEqual(user.bio, "Software developer")
        XCTAssertEqual(user.followersCount, 1000)
        XCTAssertEqual(user.followingCount, 500)
        XCTAssertEqual(user.postsCount, 250)
    }

    func testInitials_TwoWords() {
        // Given
        let user = User.mock(displayName: "John Doe")

        // When
        let initials = user.initials

        // Then
        XCTAssertEqual(initials, "JD")
    }

    func testInitials_SingleWord() {
        // Given
        let user = User.mock(displayName: "John")

        // When
        let initials = user.initials

        // Then
        XCTAssertEqual(initials, "J")
    }

    func testInitials_ThreeWords() {
        // Given
        let user = User.mock(displayName: "John Michael Doe")

        // When
        let initials = user.initials

        // Then
        XCTAssertEqual(initials, "JM") // Only first two
    }

    func testInitials_LowerCase() {
        // Given
        let user = User.mock(displayName: "john doe")

        // When
        let initials = user.initials

        // Then
        XCTAssertEqual(initials, "JD") // Should be uppercase
    }

    func testEquality() {
        // Given
        let user1 = User.mock(id: "user_1", username: "john")
        let user2 = User.mock(id: "user_1", username: "john")
        let user3 = User.mock(id: "user_2", username: "jane")

        // When/Then
        XCTAssertEqual(user1, user2)
        XCTAssertNotEqual(user1, user3)
    }
}

// MARK: - Comment Model Tests

class CommentModelTests: XCTestCase {

    func testDecode_ValidJSON() throws {
        // Given
        let json = """
        {
            "id": "comment_123",
            "post_id": "post_456",
            "author": {
                "id": "user_789",
                "username": "commenter",
                "display_name": "The Commenter"
            },
            "text": "Great post!",
            "created_at": "2025-10-18T12:00:00Z"
        }
        """
        let data = json.data(using: .utf8)!

        // When
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let comment = try decoder.decode(Comment.self, from: data)

        // Then
        XCTAssertEqual(comment.id, "comment_123")
        XCTAssertEqual(comment.postId, "post_456")
        XCTAssertEqual(comment.author.id, "user_789")
        XCTAssertEqual(comment.text, "Great post!")
    }

    func testEncode() throws {
        // Given
        let comment = Comment.mock(
            id: "comment_1",
            postId: "post_1",
            text: "Test comment"
        )

        // When
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(comment)
        let jsonString = String(data: data, encoding: .utf8)!

        // Then
        XCTAssertTrue(jsonString.contains("\"id\":\"comment_1\""))
        XCTAssertTrue(jsonString.contains("\"post_id\":\"post_1\""))
        XCTAssertTrue(jsonString.contains("\"text\":\"Test comment\""))
    }
}

// MARK: - Date Extension Tests

class DateExtensionTests: XCTestCase {

    func testTimeAgo_JustNow() {
        // Given
        let date = Date()

        // When
        let timeAgo = date.timeAgo

        // Then
        XCTAssertEqual(timeAgo, "Just now")
    }

    func testTimeAgo_Minutes() {
        // Given
        let date = Date().adding(seconds: -180) // 3 minutes ago

        // When
        let timeAgo = date.timeAgo

        // Then
        XCTAssertEqual(timeAgo, "3m ago")
    }

    func testTimeAgo_Hours() {
        // Given
        let date = Date().adding(seconds: -7200) // 2 hours ago

        // When
        let timeAgo = date.timeAgo

        // Then
        XCTAssertEqual(timeAgo, "2h ago")
    }

    func testTimeAgo_Days() {
        // Given
        let date = Date().adding(days: -3)

        // When
        let timeAgo = date.timeAgo

        // Then
        XCTAssertEqual(timeAgo, "3d ago")
    }

    func testTimeAgo_Weeks() {
        // Given
        let date = Date().adding(days: -14)

        // When
        let timeAgo = date.timeAgo

        // Then
        XCTAssertEqual(timeAgo, "2w ago")
    }

    func testTimeAgo_EdgeCase_59Seconds() {
        // Given
        let date = Date().adding(seconds: -59)

        // When
        let timeAgo = date.timeAgo

        // Then
        XCTAssertEqual(timeAgo, "Just now")
    }

    func testTimeAgo_EdgeCase_60Seconds() {
        // Given
        let date = Date().adding(seconds: -60)

        // When
        let timeAgo = date.timeAgo

        // Then
        XCTAssertEqual(timeAgo, "1m ago")
    }
}
