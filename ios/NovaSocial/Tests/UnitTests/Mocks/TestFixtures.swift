import Foundation
@testable import ICERED

/// TestFixtures - Test data factory
/// TDD: Provides consistent test data, eliminates code duplication
enum TestFixtures {

    // MARK: - User Fixtures

    static func makeUserProfile(
        id: String = UUID().uuidString,
        username: String = "testuser",
        email: String? = "test@example.com",
        displayName: String? = "Test User",
        bio: String? = nil,
        avatarUrl: String? = nil,
        coverUrl: String? = nil,
        website: String? = nil,
        location: String? = nil,
        isVerified: Bool = false,
        isPrivate: Bool = false,
        isBanned: Bool = false,
        followerCount: Int = 0,
        followingCount: Int = 0,
        postCount: Int = 0
    ) -> UserProfile {
        UserProfile(
            id: id,
            username: username,
            email: email,
            displayName: displayName,
            bio: bio,
            avatarUrl: avatarUrl,
            coverUrl: coverUrl,
            website: website,
            location: location,
            isVerified: isVerified,
            isPrivate: isPrivate,
            isBanned: isBanned,
            followerCount: followerCount,
            followingCount: followingCount,
            postCount: postCount,
            createdAt: Int64(Date().timeIntervalSince1970 * 1000),
            updatedAt: Int64(Date().timeIntervalSince1970 * 1000),
            deletedAt: nil,
            firstName: nil,
            lastName: nil,
            dateOfBirth: nil,
            gender: nil
        )
    }

    // MARK: - Auth Fixtures

    static func makeAuthResponse(
        token: String = "test_access_token",
        refreshToken: String? = "test_refresh_token",
        user: UserProfile? = nil
    ) -> AuthResponse {
        AuthResponse(
            token: token,
            refreshToken: refreshToken,
            user: user ?? makeUserProfile()
        )
    }

    // MARK: - JSON Data Fixtures

    static func makeJSONData<T: Encodable>(_ object: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(object)
    }

    static func makeHTTPResponse(
        url: URL = URL(string: "https://api.example.com/test")!,
        statusCode: Int = 200,
        headers: [String: String]? = nil
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )!
    }

    // MARK: - Error Response Fixtures

    struct ErrorResponse: Codable {
        let error: String
        let message: String
    }

    static func makeErrorResponse(
        error: String = "Test error",
        message: String = "Test error message"
    ) -> ErrorResponse {
        ErrorResponse(error: error, message: message)
    }

    static func makeErrorData(
        error: String = "Test error",
        message: String = "Test error message"
    ) throws -> Data {
        try makeJSONData(makeErrorResponse(error: error, message: message))
    }

    // MARK: - Request Verification Helpers

    /// Verify request has authorization header
    static func verifyAuthHeader(
        _ request: URLRequest,
        expectedToken: String
    ) -> Bool {
        let authHeader = request.value(forHTTPHeaderField: "Authorization")
        return authHeader == "Bearer \(expectedToken)"
    }

    /// Verify request is JSON content type
    static func verifyJSONContentType(_ request: URLRequest) -> Bool {
        let contentType = request.value(forHTTPHeaderField: "Content-Type")
        return contentType == "application/json"
    }

    /// Decode request body
    static func decodeRequestBody<T: Decodable>(_ request: URLRequest, as type: T.Type) throws -> T {
        guard let body = request.httpBody else {
            throw NSError(domain: "TestFixtures", code: 1, userInfo: [NSLocalizedDescriptionKey: "No request body"])
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: body)
    }
}

// MARK: - AuthResponse Extension for Testing

extension AuthResponse {
    /// Convenience initializer for testing
    init(token: String, refreshToken: String?, user: UserProfile) {
        // This uses a workaround since we can't directly init the struct
        // We encode and decode to create the instance
        let dict: [String: Any] = [
            "token": token,
            "refresh_token": refreshToken as Any,
            "user": [
                "id": user.id,
                "username": user.username,
                "email": user.email as Any,
                "display_name": user.displayName as Any,
                "bio": user.bio as Any,
                "avatar_url": user.avatarUrl as Any,
                "cover_url": user.coverUrl as Any,
                "website": user.website as Any,
                "location": user.location as Any,
                "is_verified": user.isVerified as Any,
                "is_private": user.isPrivate as Any,
                "is_banned": user.isBanned as Any,
                "follower_count": user.followerCount as Any,
                "following_count": user.followingCount as Any,
                "post_count": user.postCount as Any,
                "created_at": user.createdAt as Any,
                "updated_at": user.updatedAt as Any
            ]
        ]

        // Fallback: just set properties directly if possible
        // Since AuthResponse is a struct with let properties, we need JSON roundtrip
        let data = try! JSONSerialization.data(withJSONObject: dict)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self = try! decoder.decode(AuthResponse.self, from: data)
    }
}
