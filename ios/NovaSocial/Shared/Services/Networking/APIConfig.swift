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
            // AWS EKS staging environment - Ingress LoadBalancer URL
            return "http://a3326508b1e3c43239348cac7ce9ee03-1036729988.ap-northeast-1.elb.amazonaws.com"
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
    // 🧪 TESTING: Temporarily forcing staging for Ingress testing
    static var current: APIEnvironment = .staging

    // Original configuration (commented out for testing):
    // static var current: APIEnvironment = {
    //     #if DEBUG
    //     return .development
    //     #else
    //     return .production
    //     #endif
    // }()

    // MARK: - Endpoints (API v1 for most services, v2 for feed-service)
    // Most backend services use /api/v1, except feed-service which uses /api/v2/feed

    struct Graph {
        static let followers = "/api/v1/relationships/followers"
        static let following = "/api/v1/relationships/following"
        static let follow = "/api/v1/relationships/follow"
        static let unfollow = "/api/v1/relationships/unfollow"
        static let isFollowing = "/api/v1/relationships/is-following"
    }

    struct Social {
        // feed-service uses v2
        static let createLike = "/api/v2/feed/like"
        static let deleteLike = "/api/v2/feed/unlike"
        static let getLikes = "/api/v2/feed/likes"
        static let checkLiked = "/api/v2/feed/check-liked"
        static let createComment = "/api/v2/feed/comment"
        static let deleteComment = "/api/v2/feed/comment/delete"
        static let getComments = "/api/v2/feed/comments"
        static let createShare = "/api/v2/feed/share"
        static let getShareCount = "/api/v2/feed/shares/count"
        static let batchGetStats = "/api/v2/feed/stats/batch"
    }

    struct Content {
        static let getPost = "/api/v1/posts/get"
        static let createPost = "/api/v1/posts/create"
        static let updatePost = "/api/v1/posts/update"
        static let deletePost = "/api/v1/posts/delete"
        static let postsByAuthor = "/api/v1/posts/author"
        static let bookmarks = "/api/v1/posts/bookmarks"
    }

    struct Media {
        static let uploadStart = "/api/v1/uploads/start"
        static let uploadProgress = "/api/v1/uploads/progress"
        static let uploadComplete = "/api/v1/uploads/complete"
        static let reels = "/api/v1/reels"
        static let videos = "/api/v1/videos"
    }

    struct Auth {
        static let login = "/api/v1/auth/login"
        static let register = "/api/v1/auth/register"
        static let refresh = "/api/v1/auth/refresh"
        static let logout = "/api/v1/auth/logout"
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
