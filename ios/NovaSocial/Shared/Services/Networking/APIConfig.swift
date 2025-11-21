import Foundation

// MARK: - API Configuration

enum APIEnvironment {
    case development
    case staging
    case production

    var baseURL: String {
        switch self {
        case .development:
            return "http://localhost:8080"  // GraphQL Gateway for local development
        case .staging:
            return "https://staging-api.nova.social"
        case .production:
            return "https://api.nova.social"
        }
    }

    var timeout: TimeInterval {
        switch self {
        case .development:
            return 60  // Longer timeout for local debugging
        case .staging, .production:
            return 30
        }
    }
}

struct APIConfig {
    static var current: APIEnvironment = {
        #if DEBUG
        return .development
        #else
        return .production
        #endif
    }()

    // MARK: - Endpoints

    struct Graph {
        static let followers = "/api/v1/graph/followers"
        static let following = "/api/v1/graph/following"
        static let follow = "/api/v1/graph/follow"
        static let unfollow = "/api/v1/graph/unfollow"
        static let isFollowing = "/api/v1/graph/is-following"
    }

    struct Social {
        static let createLike = "/api/v1/social/like"
        static let deleteLike = "/api/v1/social/unlike"
        static let getLikes = "/api/v1/social/likes"
        static let checkLiked = "/api/v1/social/check-liked"
        static let createComment = "/api/v1/social/comment"
        static let deleteComment = "/api/v1/social/comment/delete"
        static let getComments = "/api/v1/social/comments"
        static let createShare = "/api/v1/social/share"
        static let getShareCount = "/api/v1/social/shares/count"
        static let batchGetStats = "/api/v1/social/stats/batch"
    }

    struct Content {
        static let getPost = "/api/v1/content/post"
        static let createPost = "/api/v1/content/post/create"
        static let updatePost = "/api/v1/content/post/update"
        static let deletePost = "/api/v1/content/post/delete"
        static let postsByAuthor = "/api/v1/content/posts/author"
        static let bookmarks = "/api/v1/content/bookmarks"
    }

    struct Media {
        static let uploadStart = "/api/v1/media/upload/start"
        static let uploadProgress = "/api/v1/media/upload/progress"
        static let uploadComplete = "/api/v1/media/upload/complete"
        static let reels = "/api/v1/media/reels"
        static let videos = "/api/v1/media/videos"
    }

    struct Auth {
        static let login = "/api/v1/auth/login"
        static let register = "/api/v1/auth/register"
        static let refresh = "/api/v1/auth/refresh"
        static let logout = "/api/v1/auth/logout"
        static let getUser = "/api/v2/users"  // GET /api/v2/users/{id}
        static let updateUser = "/api/v2/users"  // PUT /api/v2/users/{id}
    }

    // MARK: - Service Ports (for direct gRPC access if needed)

    struct ServicePorts {
        static let graphService = 8080
        static let contentService = 8081
        static let mediaService = 8082
        static let socialService = 8083
        static let feedService = 8084
        static let messagingService = 8085
        static let notificationService = 8086
        static let authService = 8087
    }
}

// MARK: - API Feature Flags

struct APIFeatureFlags {
    static var enableMockData = false  // For testing without backend
    static var enableRequestLogging = true  // Log API requests in debug
    static var enableOfflineMode = false  // Cache and retry failed requests
    static var maxRetryAttempts = 3
    static var retryDelay: TimeInterval = 2.0
}
