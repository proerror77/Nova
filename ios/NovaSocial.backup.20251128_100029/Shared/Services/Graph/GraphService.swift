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
}
