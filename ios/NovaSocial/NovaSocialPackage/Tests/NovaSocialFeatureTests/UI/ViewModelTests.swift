import Testing
import SwiftUI

@testable import NovaSocialFeature

// MARK: - AsyncState Tests

@Suite("AsyncState Tests")
struct AsyncStateTests {
    @Test("AsyncState.idle is equal to other idle states")
    func testAsyncStateIdleEquality() {
        let state1: AsyncState<[String]> = .idle
        let state2: AsyncState<[String]> = .idle

        #expect(state1 == state2)
    }

    @Test("AsyncState.loading is equal to other loading states")
    func testAsyncStateLoadingEquality() {
        let state1: AsyncState<[String]> = .loading
        let state2: AsyncState<[String]> = .loading

        #expect(state1 == state2)
    }

    @Test("AsyncState.success with same data is equal")
    func testAsyncStateSuccessEquality() {
        let data = ["item1", "item2"]
        let state1: AsyncState<[String]> = .success(data)
        let state2: AsyncState<[String]> = .success(data)

        #expect(state1 == state2)
    }

    @Test("AsyncState.error with same message is equal")
    func testAsyncStateErrorEquality() {
        let message = "Error message"
        let state1: AsyncState<[String]> = .error(message)
        let state2: AsyncState<[String]> = .error(message)

        #expect(state1 == state2)
    }

    @Test("AsyncState.idle differs from other states")
    func testAsyncStateInequalityWithDifferentTypes() {
        let idle: AsyncState<[String]> = .idle
        let loading: AsyncState<[String]> = .loading

        #expect(idle != loading)
    }

    @Test("AsyncState.success differs with different data")
    func testAsyncStateSuccessInequalityDifferentData() {
        let state1: AsyncState<[String]> = .success(["item1"])
        let state2: AsyncState<[String]> = .success(["item2"])

        #expect(state1 != state2)
    }

    @Test("AsyncState.error differs with different messages")
    func testAsyncStateErrorInequalityDifferentMessages() {
        let state1: AsyncState<[String]> = .error("Error 1")
        let state2: AsyncState<[String]> = .error("Error 2")

        #expect(state1 != state2)
    }
}

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

    @Test("Notification conforms to Identifiable")
    func testNotificationIdentifiable() {
        let actor = User(id: "user1", username: "john", displayName: "John Doe")
        let notification = Notification(
            id: "notif1",
            userId: "user2",
            actionType: "like",
            targetId: "post1",
            timestamp: "2025-10-19T10:00:00Z",
            actor: actor
        )

        #expect(notification.id == "notif1")
    }

    @Test("Notification conforms to Equatable")
    func testNotificationEquatable() {
        let actor = User(id: "user1", username: "john", displayName: "John Doe")
        let notif1 = Notification(
            id: "notif1",
            userId: "user2",
            actionType: "like",
            targetId: "post1",
            timestamp: "2025-10-19T10:00:00Z",
            actor: actor
        )
        let notif2 = Notification(
            id: "notif1",
            userId: "user2",
            actionType: "like",
            targetId: "post1",
            timestamp: "2025-10-19T10:00:00Z",
            actor: actor
        )

        #expect(notif1 == notif2)
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

// MARK: - Image Cache Statistics Tests

@Suite("ImageCacheStatistics Tests")
struct ImageCacheStatisticsTests {
    var stats: ImageCacheStatistics!

    mutating func setup() async {
        stats = ImageCacheStatistics()
    }

    @Test("ImageCacheStatistics tracks requests")
    func testTrackRequests() {
        stats.recordRequest()
        stats.recordRequest()
        stats.recordRequest()

        #expect(stats.totalRequests == 3)
    }

    @Test("ImageCacheStatistics tracks cache hits")
    func testTrackHits() {
        stats.recordRequest()
        stats.recordRequest()
        stats.recordHit()

        #expect(stats.totalRequests == 2)
        #expect(stats.cacheHits == 1)
    }

    @Test("ImageCacheStatistics calculates hit rate")
    func testHitRate() {
        stats.recordRequest()
        stats.recordRequest()
        stats.recordRequest()
        stats.recordRequest()
        stats.recordHit()
        stats.recordHit()

        let expectedRate = 0.5
        #expect(abs(stats.hitRate - expectedRate) < 0.001)
    }

    @Test("ImageCacheStatistics tracks bytes")
    func testTrackBytes() {
        stats.recordBytes(1024)
        stats.recordBytes(2048)

        #expect(stats.bytesLoaded == 3072)
    }

    @Test("ImageCacheStatistics can be reset")
    func testReset() {
        stats.recordRequest()
        stats.recordHit()
        stats.recordBytes(512)

        stats.reset()

        #expect(stats.totalRequests == 0)
        #expect(stats.cacheHits == 0)
        #expect(stats.bytesLoaded == 0)
    }

    @Test("ImageCacheStatistics provides debug description")
    func testDebugDescription() {
        stats.recordRequest()
        stats.recordRequest()
        stats.recordHit()

        let description = stats.debugDescription

        #expect(description.contains("Image Cache Statistics"))
        #expect(description.contains("Total Requests"))
        #expect(description.contains("Cache Hits"))
        #expect(description.contains("Hit Rate"))
    }
}
