import Foundation

// MARK: - Friends Service

/// Manages friend relationships and user connections
/// Handles adding/removing friends, searching users, and getting friend recommendations
class FriendsService {
    private let client = APIClient.shared

    // MARK: - Search Users

    /// Search for users by query string
    /// - Parameters:
    ///   - query: Search query (username, display name, etc.)
    ///   - limit: Maximum number of results (default: 20)
    ///   - offset: Pagination offset (default: 0)
    /// - Returns: Array of user profiles matching the query
    func searchUsers(query: String, limit: Int = 20, offset: Int = 0) async throws -> [UserProfile] {
        struct Response: Codable {
            let users: [UserProfile]
            let total: Int?
        }

        let response: Response = try await client.get(
            endpoint: APIConfig.Friends.searchUsers,
            queryParams: [
                "q": query,
                "limit": String(limit),
                "offset": String(offset)
            ]
        )

        return response.users
    }

    // MARK: - Friend Recommendations

    /// Get recommended friends/contacts
    /// - Parameters:
    ///   - limit: Maximum number of recommendations (default: 20)
    /// - Returns: Array of recommended user profiles
    func getRecommendations(limit: Int = 20) async throws -> [UserProfile] {
        struct Response: Codable {
            let recommendations: [UserProfile]
            let total: Int?
        }

        let response: Response = try await client.get(
            endpoint: APIConfig.Friends.getRecommendations,
            queryParams: ["limit": String(limit)]
        )

        return response.recommendations
    }

    // MARK: - Add Friend

    /// Add a user as friend
    /// - Parameter userId: ID of the user to add as friend
    /// - Throws: APIError if the request fails
    func addFriend(userId: String) async throws {
        struct Request: Codable {
            let user_id: String
        }

        struct Response: Codable {
            let success: Bool
            let message: String?
        }

        let request = Request(user_id: userId)
        let response: Response = try await client.request(
            endpoint: APIConfig.Friends.addFriend,
            method: "POST",
            body: request
        )

        guard response.success else {
            throw APIError.serverError(
                statusCode: 400,
                message: response.message ?? "Failed to add friend"
            )
        }
    }

    // MARK: - Remove Friend

    /// Remove a user from friends list
    /// - Parameter userId: ID of the user to remove
    /// - Throws: APIError if the request fails
    func removeFriend(userId: String) async throws {
        struct Request: Codable {
            let user_id: String
        }

        struct Response: Codable {
            let success: Bool
            let message: String?
        }

        let request = Request(user_id: userId)
        let response: Response = try await client.request(
            endpoint: APIConfig.Friends.removeFriend,
            method: "DELETE",
            body: request
        )

        guard response.success else {
            throw APIError.serverError(
                statusCode: 400,
                message: response.message ?? "Failed to remove friend"
            )
        }
    }

    // MARK: - Get Friends List

    /// Get user's friends list
    /// - Parameters:
    ///   - userId: User ID (optional, defaults to current user)
    ///   - limit: Maximum number of friends to return (default: 50)
    ///   - offset: Pagination offset (default: 0)
    /// - Returns: Tuple containing array of friend profiles and total count
    func getFriendsList(userId: String? = nil, limit: Int = 50, offset: Int = 0) async throws -> (friends: [UserProfile], total: Int) {
        struct Response: Codable {
            let friends: [UserProfile]
            let total: Int
        }

        var queryParams = [
            "limit": String(limit),
            "offset": String(offset)
        ]

        if let userId = userId {
            queryParams["user_id"] = userId
        }

        let response: Response = try await client.get(
            endpoint: APIConfig.Friends.getFriendsList,
            queryParams: queryParams
        )

        return (response.friends, response.total)
    }

    // MARK: - Check Friendship Status

    /// Check if the current user is friends with another user
    /// - Parameter userId: ID of the user to check
    /// - Returns: True if users are friends, false otherwise
    func isFriend(userId: String) async throws -> Bool {
        struct Response: Codable {
            let is_friend: Bool
        }

        // This endpoint might need to be added to APIConfig if not exists
        let response: Response = try await client.get(
            endpoint: "/api/v2/friends/status",
            queryParams: ["user_id": userId]
        )

        return response.is_friend
    }

    // MARK: - Friend Request Management

    /// Send a friend request to a user
    /// - Parameter userId: ID of the user to send request to
    /// - Returns: The created friend request
    func sendFriendRequest(userId: String) async throws -> FriendRequest {
        struct Request: Codable {
            let user_id: String
        }

        struct Response: Codable {
            let request: FriendRequest
        }

        let request = Request(user_id: userId)
        let response: Response = try await client.request(
            endpoint: APIConfig.Friends.sendRequest,
            method: "POST",
            body: request
        )

        return response.request
    }

    /// Get pending friend requests (received or sent)
    /// - Parameters:
    ///   - type: "received" for requests received, "sent" for requests sent
    ///   - limit: Maximum number of requests to return
    ///   - offset: Pagination offset
    /// - Returns: Tuple containing array of friend requests with user info and total count
    func getPendingRequests(
        type: FriendRequestType = .received,
        limit: Int = 20,
        offset: Int = 0
    ) async throws -> (requests: [FriendRequestWithUser], total: Int) {
        struct Response: Codable {
            let requests: [FriendRequestWithUser]
            let total: Int
        }

        let response: Response = try await client.get(
            endpoint: APIConfig.Friends.getPendingRequests,
            queryParams: [
                "type": type.rawValue,
                "limit": String(limit),
                "offset": String(offset)
            ]
        )

        return (response.requests, response.total)
    }

    /// Accept a friend request
    /// - Parameter requestId: ID of the friend request to accept
    func acceptFriendRequest(requestId: String) async throws {
        struct Request: Codable {
            let request_id: String
        }

        struct Response: Codable {
            let success: Bool
            let message: String?
        }

        let request = Request(request_id: requestId)
        let response: Response = try await client.request(
            endpoint: APIConfig.Friends.acceptRequest,
            method: "POST",
            body: request
        )

        guard response.success else {
            throw APIError.serverError(
                statusCode: 400,
                message: response.message ?? "Failed to accept friend request"
            )
        }
    }

    /// Reject a friend request
    /// - Parameter requestId: ID of the friend request to reject
    func rejectFriendRequest(requestId: String) async throws {
        struct Request: Codable {
            let request_id: String
        }

        struct Response: Codable {
            let success: Bool
            let message: String?
        }

        let request = Request(request_id: requestId)
        let response: Response = try await client.request(
            endpoint: APIConfig.Friends.rejectRequest,
            method: "POST",
            body: request
        )

        guard response.success else {
            throw APIError.serverError(
                statusCode: 400,
                message: response.message ?? "Failed to reject friend request"
            )
        }
    }

    /// Cancel a sent friend request
    /// - Parameter requestId: ID of the friend request to cancel
    func cancelFriendRequest(requestId: String) async throws {
        struct Response: Codable {
            let success: Bool
            let message: String?
        }

        let response: Response = try await client.request(
            endpoint: APIConfig.Friends.cancelRequest(requestId),
            method: "DELETE",
            body: EmptyBody()
        )

        guard response.success else {
            throw APIError.serverError(
                statusCode: 400,
                message: response.message ?? "Failed to cancel friend request"
            )
        }
    }

    /// Get the count of pending friend requests (received)
    /// - Returns: Number of pending requests
    func getPendingRequestCount() async throws -> Int {
        struct Response: Codable {
            let count: Int
        }

        let response: Response = try await client.get(
            endpoint: APIConfig.Friends.pendingCount
        )

        return response.count
    }
}

// MARK: - Empty Body Helper
private struct EmptyBody: Codable {}

// MARK: - Supporting Models

/// Friend request model
struct FriendRequest: Codable, Identifiable {
    let id: String
    let senderId: String
    let receiverId: String
    let status: FriendRequestStatus
    let createdAt: Int64
    let updatedAt: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case senderId = "sender_id"
        case receiverId = "receiver_id"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Friend request status enum
enum FriendRequestStatus: String, Codable {
    case pending = "pending"
    case accepted = "accepted"
    case rejected = "rejected"
    case cancelled = "cancelled"
}

/// Friend request type for filtering (received or sent)
enum FriendRequestType: String, Codable {
    case received
    case sent
}

/// Friend request with associated user profile for display
struct FriendRequestWithUser: Codable, Identifiable {
    let id: String
    let request: FriendRequest
    let user: UserProfile  // The other user (sender for received requests, receiver for sent requests)
    let createdAt: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case request
        case user
        case createdAt = "created_at"
    }
}

/// Friend recommendation model
struct FriendRecommendation: Codable, Identifiable {
    let id: String
    let user: UserProfile
    let reason: String?  // e.g., "mutual friends", "similar interests"
    let mutualFriendsCount: Int?
    let score: Double?  // Recommendation score

    enum CodingKeys: String, CodingKey {
        case id
        case user
        case reason
        case mutualFriendsCount = "mutual_friends_count"
        case score
    }
}
