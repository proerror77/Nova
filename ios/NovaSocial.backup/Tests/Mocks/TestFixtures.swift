import Foundation
@testable import NovaSocial

/// TestFixtures - 测试数据工厂
/// TDD: 提供一致的测试数据，消除重复代码
enum TestFixtures {

    // MARK: - User Fixtures

    static func makeUser(
        id: UUID = UUID(),
        username: String = "testuser",
        email: String = "test@example.com",
        displayName: String? = "Test User",
        bio: String? = nil,
        avatarUrl: String? = nil,
        isVerified: Bool = false
    ) -> User {
        User(
            id: id,
            username: username,
            email: email,
            displayName: displayName,
            bio: bio,
            avatarUrl: avatarUrl,
            isVerified: isVerified,
            createdAt: Date()
        )
    }

    // MARK: - Auth Fixtures

    static func makeAuthTokens(
        accessToken: String = "test_access_token",
        refreshToken: String = "test_refresh_token",
        expiresIn: Int = 900,
        tokenType: String = "Bearer"
    ) -> AuthTokens {
        AuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresIn: expiresIn,
            tokenType: tokenType
        )
    }

    static func makeAuthResponse(
        user: User? = nil,
        tokens: AuthTokens? = nil
    ) -> AuthResponse {
        AuthResponse(
            user: user ?? makeUser(),
            tokens: tokens ?? makeAuthTokens()
        )
    }

    // MARK: - Post Fixtures

    static func makePost(
        id: UUID = UUID(),
        userId: UUID = UUID(),
        imageUrl: String = "https://cdn.example.com/image.jpg",
        thumbnailUrl: String? = "https://cdn.example.com/thumb.jpg",
        caption: String? = "Test post caption",
        likeCount: Int = 10,
        commentCount: Int = 5,
        isLiked: Bool = false,
        user: User? = nil
    ) -> Post {
        Post(
            id: id,
            userId: userId,
            imageUrl: imageUrl,
            thumbnailUrl: thumbnailUrl,
            caption: caption,
            likeCount: likeCount,
            commentCount: commentCount,
            isLiked: isLiked,
            createdAt: Date(),
            user: user
        )
    }

    static func makePosts(count: Int) -> [Post] {
        (0..<count).map { index in
            makePost(
                caption: "Test post \(index)",
                likeCount: index * 10,
                commentCount: index * 5
            )
        }
    }

    static func makeFeedResponse(
        posts: [Post]? = nil,
        nextCursor: String? = nil
    ) -> FeedResponse {
        FeedResponse(
            posts: posts ?? makePosts(count: 10),
            nextCursor: nextCursor
        )
    }

    // MARK: - Comment Fixtures

    static func makeComment(
        id: UUID = UUID(),
        postId: UUID = UUID(),
        userId: UUID = UUID(),
        content: String = "Test comment",
        user: User? = nil
    ) -> Comment {
        Comment(
            id: id,
            postId: postId,
            userId: userId,
            content: content,
            createdAt: Date(),
            user: user
        )
    }

    static func makeComments(count: Int, postId: UUID) -> [Comment] {
        (0..<count).map { index in
            makeComment(
                postId: postId,
                content: "Test comment \(index)"
            )
        }
    }

    // MARK: - Notification Fixtures

    static func makeNotification(
        id: UUID = UUID(),
        userId: UUID = UUID(),
        type: NotificationType = .like,
        actorId: UUID = UUID(),
        postId: UUID? = nil,
        isRead: Bool = false
    ) -> Notification {
        Notification(
            id: id,
            userId: userId,
            type: type,
            actorId: actorId,
            postId: postId,
            isRead: isRead,
            createdAt: Date()
        )
    }

    static func makeNotifications(count: Int) -> [Notification] {
        (0..<count).map { index in
            makeNotification(
                type: index % 2 == 0 ? .like : .comment,
                isRead: index % 3 == 0
            )
        }
    }

    // MARK: - Error Fixtures

    static func makeErrorResponse(
        error: String = "Test error",
        message: String = "Test error message",
        statusCode: Int = 400
    ) -> ErrorResponse {
        ErrorResponse(
            error: error,
            message: message
        )
    }

    // MARK: - JSON Data Fixtures

    static func makeJSONData<T: Encodable>(_ object: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(object)
    }

    static func makeHTTPResponse(
        url: URL = URL(string: "https://api.example.com/test")!,
        statusCode: Int = 200
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }
}
