import Foundation

// MARK: - Social Service

/// Manages social interactions using social-service backend
/// Handles likes, comments, shares, and feeds
class SocialService {
    private let client = APIClient.shared

    // MARK: - Feeds

    /// Get user's personalized feed
    func getUserFeed(userId: String, limit: Int = 20, cursor: String? = nil) async throws -> (posts: [Post], nextCursor: String?, hasMore: Bool) {
        // TODO: Implement gRPC call to SocialService.GetUserFeed
        // Example:
        // let request = GetUserFeedRequest(user_id: userId, limit: limit, cursor: cursor)
        // let response: GetUserFeedResponse = try await client.request(endpoint: "/social/feed", body: request)
        // return (
        //     posts: response.posts,
        //     nextCursor: response.next_cursor,
        //     hasMore: response.has_more
        // )
        throw APIError.notFound
    }

    /// Get explore/discover feed
    func getExploreFeed(limit: Int = 20, cursor: String? = nil) async throws -> (posts: [Post], nextCursor: String?, hasMore: Bool) {
        // TODO: Implement gRPC call to SocialService.GetExploreFeed
        throw APIError.notFound
    }

    /// Get trending posts
    func getTrendingPosts(limit: Int = 20) async throws -> [Post] {
        // TODO: Implement gRPC call to SocialService.GetTrendingPosts
        throw APIError.notFound
    }

    // MARK: - Likes

    func createLike(postId: String, userId: String) async throws {
        struct Request: Codable {
            let post_id: String
            let user_id: String
        }

        struct Response: Codable {
            let success: Bool
        }

        let request = Request(post_id: postId, user_id: userId)
        let _: Response = try await client.request(
            endpoint: APIConfig.Social.createLike,
            body: request
        )
    }

    func deleteLike(postId: String, userId: String) async throws {
        struct Request: Codable {
            let post_id: String
            let user_id: String
        }

        struct Response: Codable {
            let success: Bool
        }

        let request = Request(post_id: postId, user_id: userId)
        let _: Response = try await client.request(
            endpoint: APIConfig.Social.deleteLike,
            body: request
        )
    }

    func getPostLikes(postId: String, limit: Int = 20, offset: Int = 0) async throws -> (userIds: [String], totalCount: Int) {
        struct Request: Codable {
            let post_id: String
            let limit: Int
            let offset: Int
        }

        struct Response: Codable {
            let user_ids: [String]
            let total_count: Int
        }

        let request = Request(post_id: postId, limit: limit, offset: offset)
        let response: Response = try await client.request(
            endpoint: APIConfig.Social.getLikes,
            body: request
        )

        return (response.user_ids, response.total_count)
    }

    func checkUserLiked(postId: String, userId: String) async throws -> Bool {
        struct Request: Codable {
            let post_id: String
            let user_id: String
        }

        struct Response: Codable {
            let liked: Bool
        }

        let request = Request(post_id: postId, user_id: userId)
        let response: Response = try await client.request(
            endpoint: APIConfig.Social.checkLiked,
            body: request
        )

        return response.liked
    }

    // MARK: - Comments

    func createComment(postId: String, content: String, parentCommentId: String? = nil) async throws -> SocialComment {
        struct Request: Codable {
            let post_id: String
            let content: String
            let parent_comment_id: String?
        }

        struct Response: Codable {
            let comment: SocialComment
        }

        let request = Request(post_id: postId, content: content, parent_comment_id: parentCommentId)
        let response: Response = try await client.request(
            endpoint: APIConfig.Social.createComment,
            body: request
        )

        return response.comment
    }

    func deleteComment(commentId: String, userId: String) async throws {
        struct Request: Codable {
            let comment_id: String
            let user_id: String
        }

        struct Response: Codable {
            let success: Bool
        }

        let request = Request(comment_id: commentId, user_id: userId)
        let _: Response = try await client.request(
            endpoint: APIConfig.Social.deleteComment,
            body: request
        )
    }

    func getComments(postId: String, limit: Int = 20, offset: Int = 0) async throws -> (comments: [SocialComment], totalCount: Int) {
        let response: GetCommentsResponse = try await client.get(
            endpoint: APIConfig.Social.getComments,
            queryParams: [
                "post_id": postId,
                "limit": String(limit),
                "offset": String(offset)
            ]
        )
        return (response.comments, response.total)
    }

    // MARK: - Shares

    func createShare(postId: String, userId: String) async throws {
        struct Request: Codable {
            let post_id: String
            let user_id: String
        }

        struct Response: Codable {
            let success: Bool
        }

        let request = Request(post_id: postId, user_id: userId)
        let _: Response = try await client.request(
            endpoint: APIConfig.Social.createShare,
            body: request
        )
    }

    func getShareCount(postId: String) async throws -> Int {
        struct Request: Codable {
            let post_id: String
        }

        struct Response: Codable {
            let count: Int
        }

        let request = Request(post_id: postId)
        let response: Response = try await client.request(
            endpoint: APIConfig.Social.getShareCount,
            body: request
        )

        return response.count
    }

    // MARK: - Batch Stats

    /// Batch fetch social stats for multiple posts
    func batchGetStats(postIds: [String]) async throws -> [String: PostStats] {
        struct Request: Codable {
            let post_ids: [String]
        }

        struct Response: Codable {
            let stats: [String: PostStats]
        }

        let request = Request(post_ids: postIds)
        let response: Response = try await client.request(
            endpoint: APIConfig.Social.batchGetStats,
            body: request
        )

        return response.stats
    }

    // MARK: - Polls (投票榜单)

    /// Get trending polls for carousel display
    func getTrendingPolls(limit: Int = 5) async throws -> [PollSummary] {
        var urlComponents = URLComponents(string: "\(APIConfig.current.baseURL)/api/v2/polls/trending")
        urlComponents?.queryItems = [URLQueryItem(name: "limit", value: String(limit))]

        guard let url = urlComponents?.url else {
            throw APIError.invalidURL
        }

        let request = client.buildRequest(url: url, method: "GET")
        let (data, response) = try await client.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let result = try decoder.decode(TrendingPollsResponse.self, from: data)
            return result.polls
        case 401:
            throw APIError.unauthorized
        case 501:
            return []  // Service not deployed yet
        default:
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: message)
        }
    }

    /// Get poll rankings
    func getPollRankings(pollId: String, limit: Int = 10) async throws -> [PollCandidate] {
        var urlComponents = URLComponents(string: "\(APIConfig.current.baseURL)/api/v2/polls/\(pollId)/rankings")
        urlComponents?.queryItems = [URLQueryItem(name: "limit", value: String(limit))]

        guard let url = urlComponents?.url else {
            throw APIError.invalidURL
        }

        let request = client.buildRequest(url: url, method: "GET")
        let (data, response) = try await client.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let result = try decoder.decode(PollRankingsResponse.self, from: data)
            return result.rankings
        case 401:
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        default:
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: message)
        }
    }

    /// Vote for a candidate
    func voteOnPoll(pollId: String, candidateId: String) async throws {
        struct VoteRequest: Codable {
            let candidate_id: String
        }

        let url = URL(string: "\(APIConfig.current.baseURL)/api/v2/polls/\(pollId)/vote")!
        var request = client.buildRequest(url: url, method: "POST")
        request.httpBody = try JSONEncoder().encode(VoteRequest(candidate_id: candidateId))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await client.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw APIError.unauthorized
        case 409:
            throw APIError.serverError(statusCode: 409, message: "Already voted")
        default:
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: message)
        }
    }
}

// MARK: - Supporting Models

struct PostStats: Codable {
    let likeCount: Int
    let commentCount: Int
    let shareCount: Int
    let isLiked: Bool?
}

/// Comment model matching backend proto: social_service.proto Comment message
struct SocialComment: Codable, Identifiable {
    let id: String
    let userId: String
    let postId: String
    let content: String
    let parentCommentId: String?
    let createdAt: String?  // ISO8601 timestamp from backend

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case postId = "post_id"
        case content
        case parentCommentId = "parent_comment_id"
        case createdAt = "created_at"
    }

    /// Convert backend timestamp to Date
    var createdDate: Date {
        guard let createdAt = createdAt else { return Date() }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: createdAt) ?? Date()
    }
}

struct GetCommentsResponse: Codable {
    let comments: [SocialComment]
    let total: Int
}

// MARK: - Poll Models

/// Summary of a poll for carousel/list display
struct PollSummary: Codable, Identifiable {
    let id: String
    let title: String
    let coverImageUrl: String?
    let pollType: String
    let status: String
    let totalVotes: Int64
    let candidateCount: Int
    let topCandidates: [CandidatePreview]?
    let tags: [String]?
    let endsAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, status, tags
        case coverImageUrl = "cover_image_url"
        case pollType = "poll_type"
        case totalVotes = "total_votes"
        case candidateCount = "candidate_count"
        case topCandidates = "top_candidates"
        case endsAt = "ends_at"
    }
}

/// Preview of a candidate (for top 3 display)
struct CandidatePreview: Codable, Identifiable {
    let id: String
    let name: String
    let avatarUrl: String?
    let rank: Int

    enum CodingKeys: String, CodingKey {
        case id, name, rank
        case avatarUrl = "avatar_url"
    }
}

/// Full candidate details with vote stats
struct PollCandidate: Codable, Identifiable {
    let id: String
    let name: String
    let avatarUrl: String?
    let description: String?
    let userId: String?
    let voteCount: Int64
    let rank: Int
    let rankChange: Int
    let votePercentage: Double

    enum CodingKeys: String, CodingKey {
        case id, name, description, rank
        case avatarUrl = "avatar_url"
        case userId = "user_id"
        case voteCount = "vote_count"
        case rankChange = "rank_change"
        case votePercentage = "vote_percentage"
    }
}

struct TrendingPollsResponse: Codable {
    let polls: [PollSummary]
}

struct PollRankingsResponse: Codable {
    let rankings: [PollCandidate]
    let totalCandidates: Int?
    let totalVotes: Int64?

    enum CodingKeys: String, CodingKey {
        case rankings
        case totalCandidates = "total_candidates"
        case totalVotes = "total_votes"
    }
}
