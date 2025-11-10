import Testing
import SwiftUI

@testable import NovaSocialFeature

// MARK: - Model Conformance Tests

@Suite("Model Conformance Tests")
struct ModelConformanceTests {
    @Test("User conforms to Identifiable")
    func testUserIdentifiable() {
        let user = User(id: "user1", username: "john", displayName: "John Doe")
        #expect(user.id == "user1")
    }

    @Test("User conforms to Equatable")
    func testUserEquatable() {
        let user1 = User(id: "user1", username: "john", displayName: "John Doe")
        let user2 = User(id: "user1", username: "john", displayName: "John Doe")

        #expect(user1 == user2)
    }

    @Test("Post conforms to Identifiable")
    func testPostIdentifiable() {
        let author = User(id: "user1", username: "john", displayName: "John Doe")
        let post = Post(id: "post1", author: author, caption: "Test", createdAt: "2025-10-19T10:00:00Z")

        #expect(post.id == "post1")
    }

    @Test("Post conforms to Equatable")
    func testPostEquatable() {
        let author = User(id: "user1", username: "john", displayName: "John Doe")
        let post1 = Post(id: "post1", author: author, caption: "Test", createdAt: "2025-10-19T10:00:00Z")
        let post2 = Post(id: "post1", author: author, caption: "Test", createdAt: "2025-10-19T10:00:00Z")

        #expect(post1 == post2)
    }
}

// MARK: - Codable Tests

@Suite("Codable Tests")
struct CodableTests {
    @Test("User decodes from JSON with snake_case")
    func testUserDecodingSnakeCase() throws {
        let json = """
        {
            "id": "user1",
            "username": "john",
            "display_name": "John Doe",
            "avatar_url": "https://example.com/avatar.jpg",
            "bio": "Test bio",
            "followers_count": 100,
            "following_count": 50,
            "posts_count": 25
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let user = try decoder.decode(User.self, from: json)

        #expect(user.id == "user1")
        #expect(user.displayName == "John Doe")
        #expect(user.avatarUrl == "https://example.com/avatar.jpg")
        #expect(user.followersCount == 100)
    }

    @Test("Post decodes from JSON with snake_case")
    func testPostDecodingSnakeCase() throws {
        let json = """
        {
            "id": "post1",
            "author": {
                "id": "user1",
                "username": "john",
                "display_name": "John Doe",
                "followers_count": 0,
                "following_count": 0,
                "posts_count": 0
            },
            "caption": "Test post",
            "image_url": null,
            "like_count": 42,
            "comment_count": 5,
            "is_liked": false,
            "created_at": "2025-10-19T10:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let post = try decoder.decode(Post.self, from: json)

        #expect(post.id == "post1")
        #expect(post.caption == "Test post")
        #expect(post.likeCount == 42)
        #expect(post.commentCount == 5)
        #expect(post.isLiked == false)
    }
}
