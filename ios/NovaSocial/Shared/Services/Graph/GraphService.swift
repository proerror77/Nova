import Foundation

// MARK: - Graph Service

/// Manages follow/follower relationships using graph-service backend
/// Handles follower edges, following edges, and relationship queries
class GraphService {
    private let client = APIClient.shared

    // MARK: - Get Relationships

    func getFollowers(userId: String, limit: Int = 20, offset: Int = 0) async throws -> (userIds: [String], totalCount: Int, hasMore: Bool) {
        struct Request: Codable {
            let user_id: String
            let limit: Int
            let offset: Int
        }

        struct Response: Codable {
            let user_ids: [String]
            let total_count: Int
            let has_more: Bool
        }

        let request = Request(user_id: userId, limit: limit, offset: offset)
        let response: Response = try await client.request(
            endpoint: APIConfig.Graph.followers,
            body: request
        )

        return (response.user_ids, response.total_count, response.has_more)
    }

    func getFollowing(userId: String, limit: Int = 20, offset: Int = 0) async throws -> (userIds: [String], totalCount: Int, hasMore: Bool) {
        struct Request: Codable {
            let user_id: String
            let limit: Int
            let offset: Int
        }

        struct Response: Codable {
            let user_ids: [String]
            let total_count: Int
            let has_more: Bool
        }

        let request = Request(user_id: userId, limit: limit, offset: offset)
        let response: Response = try await client.request(
            endpoint: APIConfig.Graph.following,
            body: request
        )

        return (response.user_ids, response.total_count, response.has_more)
    }

    // MARK: - Modify Relationships

    func followUser(followerId: String, followeeId: String) async throws {
        struct Request: Codable {
            let follower_id: String
            let followee_id: String
        }

        struct Response: Codable {
            let success: Bool
        }

        let request = Request(follower_id: followerId, followee_id: followeeId)
        let _: Response = try await client.request(
            endpoint: APIConfig.Graph.follow,
            body: request
        )
    }

    func unfollowUser(followerId: String, followeeId: String) async throws {
        struct Request: Codable {
            let follower_id: String
            let followee_id: String
        }

        struct Response: Codable {
            let success: Bool
        }

        let request = Request(follower_id: followerId, followee_id: followeeId)
        let _: Response = try await client.request(
            endpoint: APIConfig.Graph.unfollow,
            body: request
        )
    }

    // MARK: - Check Relationships

    func isFollowing(followerId: String, followeeId: String) async throws -> Bool {
        struct Request: Codable {
            let follower_id: String
            let followee_id: String
        }

        struct Response: Codable {
            let is_following: Bool
        }

        let request = Request(follower_id: followerId, followee_id: followeeId)
        let response: Response = try await client.request(
            endpoint: APIConfig.Graph.isFollowing,
            body: request
        )

        return response.is_following
    }

    /// Check if two users are mutual followers
    func areMutualFollowers(userId1: String, userId2: String) async throws -> Bool {
        struct Response: Codable {
            let areMutuals: Bool

            enum CodingKeys: String, CodingKey {
                case areMutuals = "are_mutuals"
            }
        }

        let response: Response = try await client.get(
            endpoint: APIConfig.Graph.areMutuals,
            queryParams: [
                "user_id_1": userId1,
                "user_id_2": userId2
            ]
        )

        return response.areMutuals
    }

    /// Batch check if current user is following multiple users
    func batchCheckFollowing(followerId: String, followeeIds: [String]) async throws -> [String: Bool] {
        struct Request: Codable {
            let followerId: String
            let followeeIds: [String]

            enum CodingKeys: String, CodingKey {
                case followerId = "follower_id"
                case followeeIds = "followee_ids"
            }
        }

        struct Response: Codable {
            let results: [String: Bool]
        }

        let request = Request(followerId: followerId, followeeIds: followeeIds)
        let response: Response = try await client.request(
            endpoint: APIConfig.Graph.batchCheckFollowing,
            method: "POST",
            body: request
        )

        return response.results
    }

    // MARK: - Mute Management

    /// Mute a user (hide their content without unfollowing)
    func muteUser(muterId: String, muteeId: String) async throws {
        struct Request: Codable {
            let muterId: String
            let muteeId: String

            enum CodingKeys: String, CodingKey {
                case muterId = "muter_id"
                case muteeId = "mutee_id"
            }
        }

        struct Response: Codable {
            let success: Bool
        }

        let request = Request(muterId: muterId, muteeId: muteeId)
        let _: Response = try await client.request(
            endpoint: APIConfig.Graph.mute,
            method: "POST",
            body: request
        )
    }

    /// Unmute a user
    func unmuteUser(muterId: String, muteeId: String) async throws {
        struct Response: Codable {
            let success: Bool
        }

        let _: Response = try await client.request(
            endpoint: APIConfig.Graph.unmute(muteeId),
            method: "DELETE"
        )
    }

    /// Check if a user is muted
    func isMuted(muterId: String, muteeId: String) async throws -> Bool {
        struct Response: Codable {
            let isMuted: Bool

            enum CodingKeys: String, CodingKey {
                case isMuted = "is_muted"
            }
        }

        let response: Response = try await client.get(
            endpoint: APIConfig.Graph.isMuted(muteeId),
            queryParams: ["muter_id": muterId]
        )

        return response.isMuted
    }

    // MARK: - Block Management

    /// Block a user (prevent all interactions)
    func blockUser(blockerId: String, blockedId: String, reason: String? = nil) async throws {
        struct Request: Codable {
            let blockerId: String
            let blockedId: String
            let reason: String?

            enum CodingKeys: String, CodingKey {
                case blockerId = "blocker_id"
                case blockedId = "blocked_id"
                case reason
            }
        }

        struct Response: Codable {
            let success: Bool
        }

        let request = Request(blockerId: blockerId, blockedId: blockedId, reason: reason)
        let _: Response = try await client.request(
            endpoint: APIConfig.Graph.block,
            method: "POST",
            body: request
        )
    }

    /// Unblock a user
    func unblockUser(blockerId: String, blockedId: String) async throws {
        struct Response: Codable {
            let success: Bool
        }

        let _: Response = try await client.request(
            endpoint: APIConfig.Graph.unblock(blockedId),
            method: "DELETE"
        )
    }

    /// Check if a user is blocked
    func isBlocked(blockerId: String, blockedId: String) async throws -> Bool {
        struct Response: Codable {
            let isBlocked: Bool

            enum CodingKeys: String, CodingKey {
                case isBlocked = "is_blocked"
            }
        }

        let response: Response = try await client.get(
            endpoint: APIConfig.Graph.isBlocked(blockedId),
            queryParams: ["blocker_id": blockerId]
        )

        return response.isBlocked
    }

    /// Check if there's a block relationship between two users (either direction)
    func hasBlockBetween(userId1: String, userId2: String) async throws -> Bool {
        struct Response: Codable {
            let hasBlock: Bool

            enum CodingKeys: String, CodingKey {
                case hasBlock = "has_block"
            }
        }

        let response: Response = try await client.get(
            endpoint: APIConfig.Graph.hasBlockBetween,
            queryParams: [
                "user_id_1": userId1,
                "user_id_2": userId2
            ]
        )

        return response.hasBlock
    }

    /// Get list of blocked users
    func getBlockedUsers(userId: String, limit: Int = 20, offset: Int = 0) async throws -> GetBlockedUsersResponse {
        let response: GetBlockedUsersResponse = try await client.get(
            endpoint: APIConfig.Graph.blockedUsers(userId),
            queryParams: [
                "limit": String(limit),
                "offset": String(offset)
            ]
        )

        return response
    }

    // MARK: - Relationship Status

    /// Get comprehensive relationship status between two users
    func getRelationshipStatus(userId: String, targetUserId: String) async throws -> RelationshipStatus {
        struct Response: Codable {
            let isFollowing: Bool
            let isFollowedBy: Bool
            let isMuted: Bool
            let isBlocked: Bool
            let isBlockedBy: Bool

            enum CodingKeys: String, CodingKey {
                case isFollowing = "is_following"
                case isFollowedBy = "is_followed_by"
                case isMuted = "is_muted"
                case isBlocked = "is_blocked"
                case isBlockedBy = "is_blocked_by"
            }
        }

        let response: Response = try await client.get(
            endpoint: APIConfig.Graph.relationship(targetUserId),
            queryParams: ["user_id": userId]
        )

        return RelationshipStatus(
            isFollowing: response.isFollowing,
            isFollowedBy: response.isFollowedBy,
            isMutualFollowing: response.isFollowing && response.isFollowedBy,
            isMuted: response.isMuted,
            isBlocked: response.isBlocked,
            isBlockedBy: response.isBlockedBy
        )
    }
}

// MARK: - Response Models

struct GetBlockedUsersResponse: Codable {
    let blockedUsers: [BlockedUser]
    let totalCount: Int
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case blockedUsers = "blocked_users"
        case totalCount = "total_count"
        case hasMore = "has_more"
    }
}

struct BlockedUser: Codable, Identifiable {
    let id: String
    let userId: String
    let blockedAt: Date
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case blockedAt = "blocked_at"
        case reason
    }
}

struct RelationshipStatus: Codable {
    let isFollowing: Bool
    let isFollowedBy: Bool
    let isMutualFollowing: Bool
    let isMuted: Bool
    let isBlocked: Bool
    let isBlockedBy: Bool
}
