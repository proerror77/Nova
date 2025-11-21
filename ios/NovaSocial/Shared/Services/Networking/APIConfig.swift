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

    // MARK: - Alice AI Assistant API
    struct Alice {
        static let getStatus = "/api/v2/alice/status"  // GET 獲取 Alice 服務狀態
        static let sendMessage = "/api/v2/alice/chat"  // POST 發送聊天消息
        static let voiceMode = "/api/v2/alice/voice"  // POST 語音模式
    }

    // MARK: - User Profile Settings API
    struct Profile {
        static let updateProfile = "/api/v2/users"  // PUT /api/v2/users/{id} 更新用戶資料
        static let uploadAvatar = "/api/v2/users/avatar"  // POST 上傳頭像
        static let getProfile = "/api/v2/users"  // GET /api/v2/users/{id} 獲取用戶資料
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
        static let getUserChannels = "/api/v2/users/channels"  // GET /api/v2/users/{id}/channels 獲取用戶訂閱的頻道
        static let subscribeChannel = "/api/v2/channels/subscribe"  // POST 訂閱頻道
        static let unsubscribeChannel = "/api/v2/channels/unsubscribe"  // DELETE 取消訂閱頻道
        static let getChannelDetails = "/api/v2/channels"  // GET /api/v2/channels/{id} 獲取頻道詳情
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
        static let getGroupDetails = "/api/v2/chat/groups"  // GET /api/v2/chat/groups/{id} 獲取群組詳情
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
