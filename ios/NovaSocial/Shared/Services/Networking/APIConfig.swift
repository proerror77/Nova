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
            // AWS EKS staging environment - Ingress LoadBalancer URL (Updated: 2025-11-18)
            // Note: Requires Host header "Host: api.nova.local" for Ingress routing
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

    // MARK: - Endpoints (API v2 - All services migrated to v2)
    // All backend services now use /api/v2 endpoints

    struct Graph {
        // Relationships API (v2)
        static let followers = "/api/v2/relationships/followers"
        static let following = "/api/v2/relationships/following"
        static let follow = "/api/v2/relationships/follow"
        static let unfollow = "/api/v2/relationships/unfollow"
        static let isFollowing = "/api/v2/relationships/is-following"
    }

    struct Feed {
        // Feed API (v2) - feed-service
        // Note: Backend uses GET with query parameters, not POST with body
        static let baseFeed = "/api/v2/feed"  // GET /api/v2/feed?user_id=xxx&limit=20&cursor=xxx

        // TODO: Following endpoints are defined in backend but not registered yet
        // Will return 404 until backend handlers are registered in main.rs
        // static let trending = "/api/v2/trending"
        // static let trendingVideos = "/api/v2/trending/videos"
        // static let trendingPosts = "/api/v2/trending/posts"
    }

    struct Social {
        // Social interactions API (v2) - feed-service
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
        // Content API (v2) - content-service
        static let getPost = "/api/v2/posts"  // GET /api/v2/posts/{id}
        static let createPost = "/api/v2/posts/create"
        static let updatePost = "/api/v2/posts/update"
        static let deletePost = "/api/v2/posts/delete"
        static let postsByAuthor = "/api/v2/posts/author"  // GET /api/v2/posts/author/{author_id}
        static let bookmarks = "/api/v2/posts/bookmarks"
    }

    struct Media {
        // Media API (v2) - media-service
        static let uploadStart = "/api/v2/uploads/start"
        static let uploadProgress = "/api/v2/uploads/progress"
        static let uploadComplete = "/api/v2/uploads/complete"
        static let reels = "/api/v2/reels"
        static let videos = "/api/v2/videos"  // GET /api/v2/videos/{id}
    }

    struct Auth {
        // Authentication API (v2) - identity-service
        static let login = "/api/v2/auth/login"
        static let register = "/api/v2/auth/register"
        static let refresh = "/api/v2/auth/refresh"
        static let logout = "/api/v2/auth/logout"
        static let getUser = "/api/v2/users"  // GET /api/v2/users/{id}
        static let updateUser = "/api/v2/users"  // PUT /api/v2/users/{id}
    }

    struct Search {
        // Search API (v2) - search-service
        static let search = "/api/v2/search"  // GET /api/v2/search?q={query}
        static let searchUsers = "/api/v2/search/users"  // GET /api/v2/search/users?q={query}
        static let searchPosts = "/api/v2/search/posts"  // GET /api/v2/search/posts?q={query}
    }

    struct Notification {
        // Notification API (v2) - notification-service
        static let getNotifications = "/api/v2/notifications"
        static let markRead = "/api/v2/notifications/mark-read"
        static let delete = "/api/v2/notifications"  // DELETE /api/v2/notifications/{id}
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
