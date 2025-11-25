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
            return "http://a3326508b1e3c43239348cac7ce9ee03-1036729988.ap-northeast-1.elb.amazonaws.com"  // AWS ELB staging endpoint
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
        return .staging  // Changed from .development for Feed API testing
        #else
        return .production
        #endif
    }()

    // MARK: - Endpoints

    struct Graph {
        static let followers = "/api/v2/graph/followers"
        static let following = "/api/v2/graph/following"
        static let follow = "/api/v2/graph/follow"
        static let unfollow = "/api/v2/graph/unfollow"
        static let isFollowing = "/api/v2/graph/is-following"
    }

    struct Social {
        static let createLike = "/api/v2/social/like"
        static let deleteLike = "/api/v2/social/unlike"
        static let getLikes = "/api/v2/social/likes"
        static let checkLiked = "/api/v2/social/check-liked"
        static let createComment = "/api/v2/social/comment"
        static let deleteComment = "/api/v2/social/comment/delete"
        static let getComments = "/api/v2/social/comments"
        static let createShare = "/api/v2/social/share"
        static let getShareCount = "/api/v2/social/shares/count"
        static let batchGetStats = "/api/v2/social/stats/batch"
    }

    struct Content {
        static let getPost = "/api/v2/content/post"
        static let createPost = "/api/v2/content/post/create"
        static let updatePost = "/api/v2/content/post/update"
        static let deletePost = "/api/v2/content/post/delete"
        static let postsByAuthor = "/api/v2/content/posts/author"
        static let bookmarks = "/api/v2/content/bookmarks"
    }

    struct Media {
        // 單次上傳端點：後端提供 /api/v2/media/upload
        static let uploadStart = "/api/v2/media/upload"
        static let uploadProgress = "/api/v2/media/upload"
        static let uploadComplete = "/api/v2/media/upload"
        static let reels = "/api/v2/media/reels"
        static let videos = "/api/v2/media/videos"
    }

    struct Auth {
        static let login = "/api/v2/auth/login"
        static let register = "/api/v2/auth/register"
        static let refresh = "/api/v2/auth/refresh"
        static let logout = "/api/v2/auth/logout"
        /// 單一用戶資料（包含 {id}）
        static func user(_ id: String) -> String { "/api/v2/users/\(id)" }
    }

    // MARK: - Feed API
    struct Feed {
        /// GET /api/v2/feed - 獲取用戶 Feed
        /// Query params: algo (ch|time), limit (1-100), cursor (pagination)
        static let getFeed = "/api/v2/feed"
    }

    // MARK: - Alice AI Assistant API
    struct Alice {
        static let getStatus = "/api/v2/alice/status"  // GET 獲取 Alice 服務狀態
        static let sendMessage = "/api/v2/alice/chat"  // POST 發送聊天消息
        static let voiceMode = "/api/v2/alice/voice"  // POST 語音模式
    }

    // MARK: - User Profile Settings API
    struct Profile {
        /// PUT /api/v2/users/{id} 更新用戶資料
        static func updateProfile(_ id: String) -> String { "/api/v2/users/\(id)" }
        static let uploadAvatar = "/api/v2/users/avatar"  // POST 上傳頭像
        /// GET /api/v2/users/{id} 獲取用戶資料
        static func getProfile(_ id: String) -> String { "/api/v2/users/\(id)" }
    }

    // MARK: - Friends & Social Graph API
    struct Friends {
        static let searchUsers = "/api/v2/search/users"  // GET 搜索用戶 ?q={query}
        static let getRecommendations = "/api/v2/friends/recommendations"  // GET 獲取推薦聯絡人
        static let addFriend = "/api/v2/friends/add"  // POST 添加好友
        static let removeFriend = "/api/v2/friends/remove"  // DELETE 移除好友
        static let getFriendsList = "/api/v2/friends/list"  // GET 獲取好友列表
    }

    // MARK: - Channels API
    struct Channels {
        static let getAllChannels = "/api/v2/channels"  // GET 獲取所有頻道列表
        /// GET /api/v2/users/{id}/channels 獲取用戶訂閱的頻道
        static func getUserChannels(_ userId: String) -> String { "/api/v2/users/\(userId)/channels" }
        static let subscribeChannel = "/api/v2/channels/subscribe"  // POST 訂閱頻道
        static let unsubscribeChannel = "/api/v2/channels/unsubscribe"  // DELETE 取消訂閱頻道
        /// GET /api/v2/channels/{id} 獲取頻道詳情
        static func getChannelDetails(_ channelId: String) -> String { "/api/v2/channels/\(channelId)" }
    }

    // MARK: - Account Management API
    struct Accounts {
        static let getAccounts = "/api/v2/accounts"  // GET 獲取用戶所有帳戶
        static let switchAccount = "/api/v2/accounts/switch"  // POST 切換帳戶
        static let removeAccount = "/api/v2/accounts"  // DELETE /api/v2/accounts/{id} 刪除帳戶
    }

    // MARK: - Device Management API
    struct Devices {
        static let getDevices = "/api/v2/devices"  // GET 獲取登錄設備列表
        static let logoutDevice = "/api/v2/devices/logout"  // POST 登出設備
        static let getCurrentDevice = "/api/v2/devices/current"  // GET 獲取當前設備信息
    }

    // MARK: - Invitation API
    struct Invitations {
        static let generateInviteCode = "/api/v2/invitations/generate"  // POST 生成邀請碼
        static let getInviteLink = "/api/v2/invitations/link"  // GET 獲取邀請鏈接
        static let inviteFriends = "/api/v2/invitations/send"  // POST 發送邀請
        static let getInvitationStatus = "/api/v2/invitations"  // GET 獲取邀請狀態
    }

    // MARK: - Chat & Messaging API
    struct Chat {
        static let createGroupChat = "/api/v2/chat/groups/create"  // POST 創建群組
        static let getConversations = "/api/v2/chat/conversations"  // GET 獲取對話列表
        static let sendMessage = "/api/v2/chat/messages"  // POST 發送消息
        static let getMessages = "/api/v2/chat/messages"  // GET 獲取消息歷史
        /// GET /api/v2/chat/conversations/{id} 獲取群組詳情
        static func getConversation(_ id: String) -> String { "/api/v2/chat/conversations/\(id)" }
        /// 未實作的群組成員相關端點預留，避免誤調 404
        static let getGroupDetails = "/api/v2/chat/groups"  // TODO: 後端尚未提供
        static let addGroupMembers = "/api/v2/chat/groups/members/add"  // POST 添加群組成員
        static let removeGroupMembers = "/api/v2/chat/groups/members/remove"  // DELETE 移除群組成員
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
