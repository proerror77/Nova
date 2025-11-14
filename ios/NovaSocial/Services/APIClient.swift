import Foundation

// MARK: - API Client Configuration

enum APIError: Error {
    case invalidURL
    case invalidResponse
    case networkError(Error)
    case decodingError(Error)
    case serverError(statusCode: Int, message: String)
    case unauthorized
    case notFound
}

class APIClient {
    static let shared = APIClient()

    private let baseURL = APIConfig.current.baseURL

    private let session: URLSession
    private var authToken: String?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = APIConfig.current.timeout
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    func setAuthToken(_ token: String) {
        self.authToken = token
    }

    // MARK: - Generic Request Method

    func request<T: Decodable>(
        endpoint: String,
        method: String = "POST",
        body: Encodable? = nil
    ) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            do {
                request.httpBody = try JSONEncoder().encode(body)
            } catch {
                throw APIError.decodingError(error)
            }
        }

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200...299:
                do {
                    let decoder = JSONDecoder()
                    return try decoder.decode(T.self, from: data)
                } catch {
                    throw APIError.decodingError(error)
                }
            case 401:
                throw APIError.unauthorized
            case 404:
                throw APIError.notFound
            default:
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw APIError.serverError(statusCode: httpResponse.statusCode, message: message)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }
}

// MARK: - Graph Service API (Follow/Follower relationships)

class GraphService {
    private let client = APIClient.shared

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

// MARK: - Social Service API (Likes, Comments, Shares)

class SocialService {
    private let client = APIClient.shared

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

    func createComment(postId: String, userId: String, content: String) async throws -> Comment {
        struct Request: Codable {
            let post_id: String
            let user_id: String
            let content: String
        }

        struct Response: Codable {
            let comment: Comment
        }

        let request = Request(post_id: postId, user_id: userId, content: content)
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

    func getComments(postId: String, limit: Int = 20, offset: Int = 0) async throws -> (comments: [Comment], totalCount: Int) {
        struct Request: Codable {
            let post_id: String
            let limit: Int
            let offset: Int
        }

        struct Response: Codable {
            let comments: [Comment]
            let total_count: Int
        }

        let request = Request(post_id: postId, limit: limit, offset: offset)
        let response: Response = try await client.request(
            endpoint: APIConfig.Social.getComments,
            body: request
        )

        return (response.comments, response.total_count)
    }
}

// MARK: - Content Service API

class ContentService {
    private let client = APIClient.shared

    func getPostsByAuthor(authorId: String, limit: Int = 20, offset: Int = 0) async throws -> GetPostsByAuthorResponse {
        struct Request: Codable {
            let author_id: String
            let status: String?
            let limit: Int
            let offset: Int
        }

        let request = Request(author_id: authorId, status: nil, limit: limit, offset: offset)
        return try await client.request(
            endpoint: APIConfig.Content.postsByAuthor,
            body: request
        )
    }

    func getUserBookmarks(userId: String, limit: Int = 20, offset: Int = 0) async throws -> GetUserBookmarksResponse {
        struct Request: Codable {
            let user_id: String
            let limit: Int
            let offset: Int
        }

        let request = Request(user_id: userId, limit: limit, offset: offset)
        return try await client.request(
            endpoint: APIConfig.Content.bookmarks,
            body: request
        )
    }

    func createPost(creatorId: String, content: String) async throws -> Post {
        struct Request: Codable {
            let creator_id: String
            let content: String
        }

        struct Response: Codable {
            let post: Post
        }

        let request = Request(creator_id: creatorId, content: content)
        let response: Response = try await client.request(
            endpoint: APIConfig.Content.createPost,
            body: request
        )

        return response.post
    }

    func getPost(postId: String) async throws -> Post? {
        struct Request: Codable {
            let post_id: String
        }

        struct Response: Codable {
            let post: Post?
            let found: Bool
        }

        let request = Request(post_id: postId)
        let response: Response = try await client.request(
            endpoint: APIConfig.Content.getPost,
            body: request
        )

        return response.found ? response.post : nil
    }
}

// MARK: - Media Service API

class MediaService {
    private let client = APIClient.shared

    func uploadImage(image: Data, userId: String, contentType: String = "image/jpeg") async throws -> String {
        struct StartUploadRequest: Codable {
            let user_id: String
            let file_name: String
            let file_size: Int64
            let content_type: String
        }

        struct StartUploadResponse: Codable {
            struct Upload: Codable {
                let id: String
            }
            let upload: Upload
        }

        // Start upload
        let startRequest = StartUploadRequest(
            user_id: userId,
            file_name: "avatar_\(UUID().uuidString).jpg",
            file_size: Int64(image.count),
            content_type: contentType
        )

        let startResponse: StartUploadResponse = try await client.request(
            endpoint: APIConfig.Media.uploadStart,
            body: startRequest
        )

        let uploadId = startResponse.upload.id

        // TODO: Implement actual file upload to S3/CDN
        // For now, return mock URL
        return "https://cdn.nova.social/avatars/\(uploadId).jpg"
    }
}
