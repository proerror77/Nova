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

    /// Response from like/unlike operations
    struct LikeResponse: Codable {
        let success: Bool
    }

    /// Create a like (count is managed client-side)
    func createLike(postId: String, userId: String) async throws {
        struct Request: Codable {
            let post_id: String
            let user_id: String
        }

        let request = Request(post_id: postId, user_id: userId)
        let _: LikeResponse = try await client.request(
            endpoint: APIConfig.Social.createLike,
            body: request
        )
    }

    /// Delete a like (count is managed client-side)
    func deleteLike(postId: String, userId: String) async throws {
        let _: LikeResponse = try await client.request(
            endpoint: APIConfig.Social.deleteLike(postId),
            method: "DELETE"
        )
    }

    func getPostLikes(postId: String, limit: Int = 20, offset: Int = 0) async throws -> (userIds: [String], totalCount: Int) {
        struct Response: Codable {
            let userIds: [String]
            let totalCount: Int
            // Note: CodingKeys removed - APIClient uses .convertFromSnakeCase
        }

        let response: Response = try await client.get(
            endpoint: APIConfig.Social.getLikes,
            queryParams: [
                "post_id": postId,
                "limit": String(limit),
                "offset": String(offset)
            ]
        )

        return (response.userIds, response.totalCount)
    }

    func checkUserLiked(postId: String, userId: String) async throws -> Bool {
        struct Response: Codable {
            let liked: Bool
        }

        let response: Response = try await client.get(
            endpoint: APIConfig.Social.checkLiked,
            queryParams: [
                "post_id": postId
            ]
        )

        return response.liked
    }

    /// Batch check if user has liked multiple posts (fixes like status inconsistency after refresh)
    /// Returns a Set of post IDs that the user has liked
    func batchCheckLiked(postIds: [String]) async throws -> Set<String> {
        struct Request: Codable {
            let postIds: [String]

            enum CodingKeys: String, CodingKey {
                case postIds = "post_ids"
            }
        }

        struct Response: Codable {
            let likedPostIds: [String]
            // Note: APIClient uses .convertFromSnakeCase
        }

        let request = Request(postIds: postIds)
        let response: Response = try await client.request(
            endpoint: APIConfig.Social.batchCheckLiked,
            body: request
        )

        return Set(response.likedPostIds)
    }

    /// Get posts liked by a user (paginated)
    func getUserLikedPosts(userId: String, limit: Int = 20, offset: Int = 0) async throws -> (postIds: [String], total: Int) {
        struct Response: Codable {
            let postIds: [String]
            let total: Int
            // Note: CodingKeys removed - APIClient uses .convertFromSnakeCase
        }

        let response: Response = try await client.get(
            endpoint: APIConfig.Social.getUserLikedPosts(userId),
            queryParams: [
                "limit": String(limit),
                "offset": String(offset)
            ]
        )

        return (response.postIds, response.total)
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

    func deleteComment(commentId: String) async throws {
        struct Request: Codable {
            let comment_id: String
        }

        // Backend returns empty response (200 with no body)
        try await client.delete(
            endpoint: APIConfig.Social.deleteComment,
            body: Request(comment_id: commentId)
        )
    }

    func getComments(postId: String, limit: Int = 20, offset: Int = 0, viewerUserId: String? = nil) async throws -> (comments: [SocialComment], totalCount: Int) {
        var queryParams: [String: String] = [
            "post_id": postId,
            "limit": String(limit),
            "offset": String(offset)
        ]

        // Add viewer_user_id to populate like_count and is_liked_by_viewer in response
        if let viewerId = viewerUserId {
            queryParams["viewer_user_id"] = viewerId
        }

        let response: GetCommentsResponse = try await client.get(
            endpoint: APIConfig.Social.getComments,
            queryParams: queryParams
        )
        return (response.comments, response.total)
    }

    // MARK: - Comment Likes (IG/小红书风格评论点赞)

    /// Response for comment like operations
    struct CommentLikeResponse: Codable {
        let likeCount: Int64

        enum CodingKeys: String, CodingKey {
            case likeCount = "like_count"
        }
    }

    /// Like a comment
    func createCommentLike(commentId: String, userId: String) async throws -> CommentLikeResponse {
        struct Request: Codable {
            let comment_id: String
            let user_id: String
        }

        let request = Request(comment_id: commentId, user_id: userId)
        return try await client.request(
            endpoint: APIConfig.Social.createCommentLike,
            body: request
        )
    }

    /// Unlike a comment
    func deleteCommentLike(commentId: String, userId: String) async throws -> CommentLikeResponse {
        return try await client.request(
            endpoint: APIConfig.Social.deleteCommentLike(commentId),
            method: "DELETE"
        )
    }

    /// Check if user has liked a comment
    func checkCommentLiked(commentId: String, userId: String) async throws -> Bool {
        struct Response: Codable {
            let liked: Bool
        }

        let response: Response = try await client.get(
            endpoint: APIConfig.Social.checkCommentLiked(commentId),
            queryParams: ["user_id": userId]
        )
        return response.liked
    }

    /// Get like count for a comment
    func getCommentLikes(commentId: String) async throws -> Int {
        struct Response: Codable {
            let likeCount: Int

            enum CodingKeys: String, CodingKey {
                case likeCount = "like_count"
            }
        }

        let response: Response = try await client.get(
            endpoint: APIConfig.Social.getCommentLikes(commentId)
        )
        return response.likeCount
    }

    /// Batch check if user has liked multiple comments (fixes N+1 API calls)
    /// Returns a dictionary mapping comment IDs to their liked status
    func batchCheckCommentLiked(commentIds: [String], userId: String) async throws -> [String: Bool] {
        struct Request: Codable {
            let commentIds: [String]

            enum CodingKeys: String, CodingKey {
                case commentIds = "comment_ids"
            }
        }

        struct Response: Codable {
            let likedStatus: [String: Bool]

            enum CodingKeys: String, CodingKey {
                case likedStatus = "liked_status"
            }
        }

        // Handle empty input
        guard !commentIds.isEmpty else {
            return [:]
        }

        // Limit to 100 comments per request
        let limitedIds = Array(commentIds.prefix(100))

        let request = Request(commentIds: limitedIds)
        let response: Response = try await client.request(
            endpoint: APIConfig.Social.batchCheckCommentLiked,
            body: request
        )
        return response.likedStatus
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
        struct Response: Codable {
            let count: Int
        }

        let response: Response = try await client.get(
            endpoint: APIConfig.Social.getShareCount(postId)
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

    // MARK: - Bookmarks

    /// Create a bookmark for a post
    func createBookmark(postId: String, userId: String) async throws {
        struct Request: Codable {
            let post_id: String
            let user_id: String
        }

        struct Response: Codable {
            let success: Bool
        }

        let request = Request(post_id: postId, user_id: userId)
        let _: Response = try await client.request(
            endpoint: APIConfig.Social.createBookmark,
            body: request
        )
    }

    /// Delete a bookmark from a post
    func deleteBookmark(postId: String) async throws {
        struct Response: Codable {
            let success: Bool
        }

        let _: Response = try await client.request(
            endpoint: APIConfig.Social.deleteBookmark(postId),
            method: "DELETE"
        )
    }

    /// Get user's bookmarked posts
    func getBookmarks(userId: String? = nil, limit: Int = 20, offset: Int = 0) async throws -> (postIds: [String], totalCount: Int) {
        struct Response: Codable {
            let postIds: [String]
            let totalCount: Int
            // Note: CodingKeys removed - APIClient uses .convertFromSnakeCase
        }

        var queryParams: [String: String] = [
            "limit": String(limit),
            "offset": String(offset)
        ]

        // Add user_id if provided (for viewing other users' saved posts)
        if let userId = userId {
            queryParams["user_id"] = userId
        }

        let response: Response = try await client.get(
            endpoint: APIConfig.Social.getBookmarks,
            queryParams: queryParams
        )

        return (response.postIds, response.totalCount)
    }

    /// Check if user has bookmarked a post
    func checkBookmarked(postId: String) async throws -> Bool {
        struct Response: Codable {
            let bookmarked: Bool
        }

        let response: Response = try await client.get(
            endpoint: APIConfig.Social.checkBookmarked(postId)
        )

        return response.bookmarked
    }

    /// Batch check if user has bookmarked multiple posts
    func batchCheckBookmarked(postIds: [String]) async throws -> Set<String> {
        struct Request: Codable {
            let postIds: [String]

            enum CodingKeys: String, CodingKey {
                case postIds = "post_ids"
            }
        }

        struct Response: Codable {
            let bookmarkedPostIds: [String]
            // Note: CodingKeys removed - APIClient uses .convertFromSnakeCase
        }

        let request = Request(postIds: postIds)
        let response: Response = try await client.request(
            endpoint: APIConfig.Social.batchCheckBookmarked,
            body: request
        )

        return Set(response.bookmarkedPostIds)
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

    // MARK: - Poll Management

    /// Get active polls
    func getActivePolls(limit: Int = 20) async throws -> [PollSummary] {
        let response: TrendingPollsResponse = try await client.get(
            endpoint: APIConfig.Poll.getActivePolls,
            queryParams: ["limit": String(limit)]
        )
        return response.polls
    }

    /// Create a new poll
    func createPoll(
        title: String,
        coverImageUrl: String? = nil,
        pollType: String = "ranking",
        tags: [String]? = nil,
        endsAt: Date? = nil,
        candidates: [PollCandidateInput]
    ) async throws -> PollDetail {
        struct Request: Codable {
            let title: String
            let coverImageUrl: String?
            let pollType: String
            let tags: [String]?
            let endsAt: String?
            let candidates: [PollCandidateInput]

            enum CodingKeys: String, CodingKey {
                case title
                case coverImageUrl = "cover_image_url"
                case pollType = "poll_type"
                case tags
                case endsAt = "ends_at"
                case candidates
            }
        }

        let request = Request(
            title: title,
            coverImageUrl: coverImageUrl,
            pollType: pollType,
            tags: tags,
            endsAt: endsAt?.ISO8601Format(),
            candidates: candidates
        )

        return try await client.request(
            endpoint: APIConfig.Poll.createPoll,
            method: "POST",
            body: request
        )
    }

    /// Get poll details
    func getPoll(pollId: String) async throws -> PollDetail {
        return try await client.get(endpoint: APIConfig.Poll.getPoll(pollId))
    }

    /// Unvote (remove vote from poll)
    func unvoteOnPoll(pollId: String) async throws {
        struct EmptyResponse: Codable {}
        let _: EmptyResponse = try await client.request(
            endpoint: APIConfig.Poll.unvote(pollId),
            method: "DELETE"
        )
    }

    /// Check if user has voted on a poll
    func checkPollVoted(pollId: String) async throws -> Bool {
        struct Response: Codable {
            let voted: Bool
            let candidateId: String?

            enum CodingKeys: String, CodingKey {
                case voted
                case candidateId = "candidate_id"
            }
        }

        let response: Response = try await client.get(endpoint: APIConfig.Poll.checkVoted(pollId))
        return response.voted
    }

    /// Add a candidate to an existing poll
    func addPollCandidate(pollId: String, candidate: PollCandidateInput) async throws -> PollCandidate {
        return try await client.request(
            endpoint: APIConfig.Poll.addCandidate(pollId),
            method: "POST",
            body: candidate
        )
    }

    /// Remove a candidate from a poll
    func removePollCandidate(pollId: String, candidateId: String) async throws {
        struct EmptyResponse: Codable {}
        let _: EmptyResponse = try await client.request(
            endpoint: APIConfig.Poll.removeCandidate(pollId: pollId, candidateId: candidateId),
            method: "DELETE"
        )
    }

    /// Close a poll (end voting)
    func closePoll(pollId: String) async throws {
        struct EmptyResponse: Codable {}
        let _: EmptyResponse = try await client.request(
            endpoint: APIConfig.Poll.closePoll(pollId),
            method: "POST"
        )
    }

    /// Delete a poll
    func deletePoll(pollId: String) async throws {
        struct EmptyResponse: Codable {}
        let _: EmptyResponse = try await client.request(
            endpoint: APIConfig.Poll.deletePoll(pollId),
            method: "DELETE"
        )
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
/// Note: Using camelCase property names that match APIClient's convertFromSnakeCase strategy
struct SocialComment: Codable, Identifiable {
    let id: String
    let userId: String
    let postId: String
    let content: String
    let parentCommentId: String?
    let createdAt: String?  // ISO8601 timestamp from backend

    // Author information (enriched by graphql-gateway)
    let authorUsername: String?
    let authorDisplayName: String?
    let authorAvatarUrl: String?

    // Engagement data (populated when viewer_user_id is provided in GetCommentsRequest)
    let likeCount: Int64?           // Total likes on this comment
    let isLikedByViewer: Bool?      // Whether the viewer has liked this comment

    /// Account type used when comment was created: "primary" (real name) or "alias"
    let authorAccountType: String?

    // Note: CodingKeys removed - APIClient uses .convertFromSnakeCase which automatically
    // converts snake_case JSON keys (user_id, post_id, etc.) to camelCase Swift properties

    /// Convert backend timestamp to Date
    var createdDate: Date {
        guard let createdAt = createdAt else { return Date() }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: createdAt) ?? Date()
    }

    /// Display name for the comment author with fallback
    var displayAuthorName: String {
        if let displayName = authorDisplayName, !displayName.isEmpty {
            return displayName
        }
        if let username = authorUsername, !username.isEmpty {
            return username
        }
        // Fallback to truncated userId
        return "User \(userId.prefix(8))"
    }
}

struct GetCommentsResponse: Codable {
    let comments: [SocialComment]
    let total: Int
}

// MARK: - Poll Models

/// Summary of a poll for carousel/list display
/// Note: Uses automatic snake_case conversion via JSONDecoder.keyDecodingStrategy
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
}

/// Preview of a candidate (for top 3 display)
/// Note: Uses automatic snake_case conversion via JSONDecoder.keyDecodingStrategy
struct CandidatePreview: Codable, Identifiable {
    let id: String
    let name: String
    let avatarUrl: String?
    let rank: Int
}

/// Full candidate details with vote stats
/// Note: Uses automatic snake_case conversion via JSONDecoder.keyDecodingStrategy
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
}

struct TrendingPollsResponse: Codable {
    let polls: [PollSummary]
}

/// Note: Uses automatic snake_case conversion via JSONDecoder.keyDecodingStrategy
struct PollRankingsResponse: Codable {
    let rankings: [PollCandidate]
    let totalCandidates: Int?
    let totalVotes: Int64?
}

/// Poll candidate input for creating polls
struct PollCandidateInput: Codable {
    let name: String
    let avatarUrl: String?
    let description: String?
    let userId: String?

    enum CodingKeys: String, CodingKey {
        case name
        case avatarUrl = "avatar_url"
        case description
        case userId = "user_id"
    }
}

/// Detailed poll information
struct PollDetail: Codable, Identifiable {
    let id: String
    let title: String
    let coverImageUrl: String?
    let pollType: String
    let status: String
    let totalVotes: Int64
    let candidateCount: Int
    let candidates: [PollCandidate]?
    let tags: [String]?
    let createdAt: Date
    let endsAt: Date?
    let closedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case status
        case tags
        case coverImageUrl = "cover_image_url"
        case pollType = "poll_type"
        case totalVotes = "total_votes"
        case candidateCount = "candidate_count"
        case candidates
        case createdAt = "created_at"
        case endsAt = "ends_at"
        case closedAt = "closed_at"
    }
}
