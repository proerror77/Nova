import Foundation

// MARK: - API Configuration

enum APIEnvironment {
    case development
    case staging
    case production

    var baseURL: String {
        switch self {
        case .development:
            // Local development server
            return ProcessInfo.processInfo.environment["NOVA_DEV_URL"] ?? "http://localhost:8080"
        case .staging:
            // Staging URL from environment or Info.plist
            if let stagingURL = ProcessInfo.processInfo.environment["NOVA_STAGING_URL"], !stagingURL.isEmpty {
                return stagingURL
            }
            if let stagingURL = Bundle.main.infoDictionary?["NOVA_STAGING_URL"] as? String,
               !stagingURL.isEmpty,
               !stagingURL.hasPrefix("$(") {  // Skip unresolved build variables
                return stagingURL
            }
            // Staging API via LoadBalancer (graphql-gateway-lb)
            return "http://34.104.179.123"
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

    /// Resource timeout (for large uploads/downloads)
    var resourceTimeout: TimeInterval {
        300
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
        /// GET /api/v2/content/{id} - Get post by ID
        static func getPost(_ id: String) -> String { "/api/v2/content/\(id)" }
        /// GET /api/v2/content/user/{user_id} - Get posts by user
        static func postsByUser(_ userId: String) -> String { "/api/v2/content/user/\(userId)" }
        /// POST /api/v2/content - Create new post
        static let createPost = "/api/v2/content"
        /// PUT /api/v2/content/{id} - Update post
        static func updatePost(_ id: String) -> String { "/api/v2/content/\(id)" }
        /// DELETE /api/v2/content/{id} - Delete post
        static func deletePost(_ id: String) -> String { "/api/v2/content/\(id)" }
        // Legacy endpoints (deprecated)
        static let getPostLegacy = "/api/v2/content/post"
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
        /// POST 註冊 - 需要 invite_code: {email, username, password, invite_code}
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
        /// GET /api/v2/feed/trending - 獲取熱門 Feed
        static let getTrending = "/api/v2/feed/trending"
    }

    // MARK: - Poll API (投票榜單)
    struct Poll {
        /// GET /api/v2/polls/trending - 獲取熱門投票榜單
        static let getTrendingPolls = "/api/v2/polls/trending"
        /// GET /api/v2/polls/active - 獲取進行中的投票
        static let getActivePolls = "/api/v2/polls/active"
        /// POST /api/v2/polls - 創建投票
        static let createPoll = "/api/v2/polls"
        /// GET /api/v2/polls/{id} - 獲取投票詳情
        static func getPoll(_ id: String) -> String { "/api/v2/polls/\(id)" }
        /// POST /api/v2/polls/{id}/vote - 投票
        static func vote(_ pollId: String) -> String { "/api/v2/polls/\(pollId)/vote" }
        /// DELETE /api/v2/polls/{id}/vote - 取消投票
        static func unvote(_ pollId: String) -> String { "/api/v2/polls/\(pollId)/vote" }
        /// GET /api/v2/polls/{id}/voted - 檢查是否已投票
        static func checkVoted(_ pollId: String) -> String { "/api/v2/polls/\(pollId)/voted" }
        /// GET /api/v2/polls/{id}/rankings - 獲取排名
        static func getRankings(_ pollId: String) -> String { "/api/v2/polls/\(pollId)/rankings" }
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

    // MARK: - Invitation API (邀請制系統)
    struct Invitations {
        // 生成邀請碼
        static let generate = "/api/v2/auth/invites"  // POST 生成新邀請碼
        // 列表我的邀請碼
        static let list = "/api/v2/auth/invites"  // GET 獲取已生成的邀請碼列表
        // 邀請統計
        static let stats = "/api/v2/auth/invites/stats"  // GET {total_generated, total_redeemed, total_pending, total_expired}
        // 配額查詢
        static let quota = "/api/v2/auth/invites/quota"  // GET {total_quota, used_quota, remaining_quota, successful_referrals}
        // 發送邀請 (SMS/Email/Link)
        static let send = "/api/v2/auth/invites/send"  // POST {channel: "sms"|"email"|"link", recipient?, message?}
        // 驗證邀請碼 (註冊前檢查 - 無需認證)
        static let validate = "/api/v2/auth/invites/validate"  // GET ?code=XXXXX
        // 推薦資訊
        static let referrals = "/api/v2/auth/referrals"  // GET 獲取推薦人和被推薦人列表
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

    // MARK: - Relationships & Privacy API (realtime-chat-service)
    struct Relationships {
        // Block Management
        static let blockUser = "/api/v2/blocks"  // POST 封鎖用戶 {user_id, reason?}
        /// DELETE /api/v2/blocks/{user_id} 解除封鎖
        static func unblockUser(_ userId: String) -> String { "/api/v2/blocks/\(userId)" }
        static let getBlockedUsers = "/api/v2/blocks"  // GET 獲取封鎖列表 ?limit=&offset=

        // Relationship Status
        /// GET /api/v2/relationships/{user_id} 獲取與用戶的關係狀態
        static func getRelationship(_ userId: String) -> String { "/api/v2/relationships/\(userId)" }

        // Privacy Settings
        static let getPrivacySettings = "/api/v2/settings/privacy"  // GET 獲取私訊權限設定
        static let updatePrivacySettings = "/api/v2/settings/privacy"  // PUT 更新私訊權限 {dm_permission: "anyone"|"followers"|"mutuals"|"nobody"}

        // Message Requests (when dm_permission restricts non-followers)
        static let getMessageRequests = "/api/v2/message-requests"  // GET 獲取待處理的訊息請求
        /// POST /api/v2/message-requests/{id}/accept 接受訊息請求
        static func acceptMessageRequest(_ requestId: String) -> String { "/api/v2/message-requests/\(requestId)/accept" }
        /// POST /api/v2/message-requests/{id}/reject 拒絕訊息請求
        static func rejectMessageRequest(_ requestId: String) -> String { "/api/v2/message-requests/\(requestId)/reject" }
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
