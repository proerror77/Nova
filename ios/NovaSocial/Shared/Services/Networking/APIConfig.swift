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
        static let areMutuals = "/api/v2/graph/are-mutuals"
        static let batchCheckFollowing = "/api/v2/graph/batch-check-following"

        // Mute endpoints
        static let mute = "/api/v2/graph/mute"
        static func unmute(_ muteeId: String) -> String { "/api/v2/graph/mute/\(muteeId)" }
        static func isMuted(_ muteeId: String) -> String { "/api/v2/graph/is-muted/\(muteeId)" }

        // Block endpoints
        static let block = "/api/v2/graph/block"
        static func unblock(_ blockedId: String) -> String { "/api/v2/graph/block/\(blockedId)" }
        static func isBlocked(_ blockedId: String) -> String { "/api/v2/graph/is-blocked/\(blockedId)" }
        static let hasBlockBetween = "/api/v2/graph/has-block-between"
        static func blockedUsers(_ userId: String) -> String { "/api/v2/graph/blocked/\(userId)" }

        // Relationship status
        static func relationship(_ userId: String) -> String { "/api/v2/graph/relationship/\(userId)" }
    }

    struct Social {
        static let createLike = "/api/v2/social/like"
        static func deleteLike(_ postId: String) -> String { "/api/v2/social/unlike/\(postId)" }
        static func getLikes(_ postId: String) -> String { "/api/v2/social/likes/\(postId)" }
        static func checkLiked(_ postId: String) -> String { "/api/v2/social/check-liked/\(postId)" }
        static let createComment = "/api/v2/social/comment"
        static func deleteComment(_ commentId: String) -> String { "/api/v2/social/comment/\(commentId)" }
        static func getComments(_ postId: String) -> String { "/api/v2/social/comments/\(postId)" }
        static let createShare = "/api/v2/social/share"
        static func getShareCount(_ postId: String) -> String { "/api/v2/social/shares/count/\(postId)" }
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
        /// GET /api/v2/posts/recent - Get recent posts
        static let recentPosts = "/api/v2/posts/recent"
        /// GET /api/v2/posts/trending - Get trending posts
        static let trendingPosts = "/api/v2/posts/trending"
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

        // Password Management
        static let changePassword = "/api/v2/auth/change-password"
        static let requestPasswordReset = "/api/v2/auth/request-password-reset"
        static let resetPassword = "/api/v2/auth/reset-password"

        // Token Management
        static let verifyToken = "/api/v2/auth/verify-token"
        static let revokeToken = "/api/v2/auth/revoke-token"
        static let revokeAllTokens = "/api/v2/auth/revoke-all-tokens"

        // Session Management
        static func sessions(_ userId: String) -> String { "/api/v2/auth/sessions/\(userId)" }
        static let verifyPassword = "/api/v2/auth/verify-password"
    }

    // MARK: - Feed API
    struct Feed {
        /// GET /api/v2/feed - 獲取用戶 Feed (需要 JWT 認證)
        /// Query params: algo (ch|time), limit (1-100), cursor (pagination)
        static let getFeed = "/api/v2/feed"
        /// GET /api/v2/feed/user/{user_id} - 獲取特定用戶的 Feed
        static func getUserFeed(_ userId: String) -> String { "/api/v2/feed/user/\(userId)" }
        /// GET /api/v2/feed/explore - 探索 Feed (發現新內容)
        static let getExplore = "/api/v2/feed/explore"
        /// GET /api/v2/feed/trending - 熱門 Feed
        static let getTrendingFeed = "/api/v2/feed/trending"
        /// GET /api/v2/guest/feed/trending - 獲取熱門 Feed (無需認證，Guest Mode)
        /// 注意：此端點與認證端點分離以避免 Actix-web 路由衝突
        static let getTrending = "/api/v2/guest/feed/trending"
        /// GET /api/v2/feed/recommended-creators - 获取推荐创作者
        static let getRecommendedCreators = "/api/v2/feed/recommended-creators"
        /// POST /api/v2/feed/rank - 对帖子进行排序
        static let rankPosts = "/api/v2/feed/rank"
        /// POST /api/v2/feed/invalidate-cache - 清除信息流缓存
        static let invalidateCache = "/api/v2/feed/invalidate-cache"
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
        /// POST /api/v2/polls/{id}/candidates - 添加候選項
        static func addCandidate(_ pollId: String) -> String { "/api/v2/polls/\(pollId)/candidates" }
        /// DELETE /api/v2/polls/{id}/candidates/{candidateId} - 刪除候選項
        static func removeCandidate(pollId: String, candidateId: String) -> String { "/api/v2/polls/\(pollId)/candidates/\(candidateId)" }
        /// POST /api/v2/polls/{id}/close - 結束投票
        static func closePoll(_ pollId: String) -> String { "/api/v2/polls/\(pollId)/close" }
        /// DELETE /api/v2/polls/{id} - 刪除投票
        static func deletePoll(_ pollId: String) -> String { "/api/v2/polls/\(pollId)" }
    }

    // MARK: - Alice AI Assistant API
    struct Alice {
        static let getStatus = "/api/v2/alice/status"  // GET 獲取 Alice 服務狀態
        static let sendMessage = "/api/v2/alice/chat"  // POST 發送聊天消息
        static let voiceMode = "/api/v2/alice/voice"  // POST 語音模式
    }

    // MARK: - AI Configuration (Backend Proxy)
    /// AI requests are proxied through our backend to protect API keys
    /// The backend handles authentication with third-party AI providers
    struct AI {
        /// Backend AI proxy endpoint - API key is handled server-side
        static var baseURL: String {
            "\(current.baseURL)/api/v2/ai"
        }
        /// Empty - API key is managed by backend, not exposed to client
        static let apiKey = ""
    }

    // MARK: - User Profile Settings API
    struct Profile {
        /// PUT /api/v2/users/{id} 更新用戶資料
        static func updateProfile(_ id: String) -> String { "/api/v2/users/\(id)" }
        static let uploadAvatar = "/api/v2/users/avatar"  // POST 上傳頭像
        /// GET /api/v2/users/{id} 獲取用戶資料
        static func getProfile(_ id: String) -> String { "/api/v2/users/\(id)" }
    }

    // MARK: - User Settings API
    struct Settings {
        /// GET /api/v2/auth/users/{id}/settings 獲取用戶設定
        /// NOTE: HTTP 網關目前將使用者設定掛在 auth-service 之下，
        /// 對應 backend/proto/services/auth_service.proto GetUserSettings。
        /// 如果之後遷移到 user-service，請同步更新為 /api/v2/users/{id}/settings。
        static func getSettings(_ userId: String) -> String { "/api/v2/auth/users/\(userId)/settings" }
        /// PUT /api/v2/auth/users/{id}/settings 更新用戶設定
        static func updateSettings(_ userId: String) -> String { "/api/v2/auth/users/\(userId)/settings" }
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

    // MARK: - Notifications API
    struct Notifications {
        /// GET /api/v2/notifications - Get notifications list
        static let getNotifications = "/api/v2/notifications"
        /// GET /api/v2/notifications/{id} - Get single notification
        static func getNotification(_ id: String) -> String { "/api/v2/notifications/\(id)" }
        /// POST /api/v2/notifications - Create notification
        static let createNotification = "/api/v2/notifications"
        /// POST /api/v2/notifications/{id}/read - Mark notification as read
        static func markRead(_ id: String) -> String { "/api/v2/notifications/\(id)/read" }
        /// POST /api/v2/notifications/read-all - Mark all notifications as read
        static let markAllRead = "/api/v2/notifications/read-all"
        /// DELETE /api/v2/notifications/{id} - Delete notification
        static func deleteNotification(_ id: String) -> String { "/api/v2/notifications/\(id)" }
        /// GET /api/v2/notifications/unread-count - Get unread count
        static let unreadCount = "/api/v2/notifications/unread-count"
        /// GET /api/v2/notifications/stats - Get notification statistics
        static let stats = "/api/v2/notifications/stats"
        /// GET /api/v2/notifications/preferences - Get notification preferences
        static let getPreferences = "/api/v2/notifications/preferences"
        /// PUT /api/v2/notifications/preferences - Update notification preferences
        static let updatePreferences = "/api/v2/notifications/preferences"
        /// POST /api/v2/notifications/push-token - Register push token
        static let registerPushToken = "/api/v2/notifications/push-token"
        /// DELETE /api/v2/notifications/push-token/{token} - Unregister push token
        static func unregisterPushToken(_ token: String) -> String { "/api/v2/notifications/push-token/\(token)" }
        /// POST /api/v2/notifications/batch - Batch create notifications
        static let batchCreate = "/api/v2/notifications/batch"
    }

    // MARK: - Chat & Messaging API
    struct Chat {
        // Conversations
        static let createGroupChat = "/api/v2/chat/groups/create"  // POST 創建群組
        static let getConversations = "/api/v2/chat/conversations"  // GET 獲取對話列表
        static let createConversation = "/api/v2/chat/conversations"  // POST 創建對話
        /// GET /api/v2/chat/conversations/{id} 獲取會話詳情
        static func getConversation(_ id: String) -> String { "/api/v2/chat/conversations/\(id)" }
        /// PUT /api/v2/chat/conversations/{id} 更新會話資訊（名稱、頭像等）
        static func updateConversation(_ id: String) -> String { "/api/v2/chat/conversations/\(id)" }

        // Messages
        /// POST /api/v2/chat/messages 發送消息（conversation_id 在 body 中）
        static let sendMessage = "/api/v2/chat/messages"
        /// GET /api/v2/chat/messages 獲取消息歷史（使用 conversation_id 查詢參數）
        static let getMessages = "/api/v2/chat/messages"
        /// PUT /api/v2/chat/messages/{id} 編輯消息
        static func editMessage(_ messageId: String) -> String { "/api/v2/chat/messages/\(messageId)" }
        /// DELETE /api/v2/chat/messages/{id} 刪除消息
        static func deleteMessage(_ messageId: String) -> String { "/api/v2/chat/messages/\(messageId)" }
        /// POST /api/v2/chat/conversations/{conversationId}/messages/{messageId}/recall 撤回消息
        static func recallMessage(conversationId: String, messageId: String) -> String {
            "/api/v2/chat/conversations/\(conversationId)/messages/\(messageId)/recall"
        }

        // Reactions
        /// POST /messages/{id}/reactions 添加表情回應
        static func addReaction(_ messageId: String) -> String { "/messages/\(messageId)/reactions" }
        /// GET /messages/{id}/reactions 獲取消息的所有表情回應
        static func getReactions(_ messageId: String) -> String { "/messages/\(messageId)/reactions" }
        /// DELETE /messages/{mid}/reactions/{rid} 刪除表情回應
        static func deleteReaction(messageId: String, reactionId: String) -> String {
            "/messages/\(messageId)/reactions/\(reactionId)"
        }

        // Group Management
        static let createGroup = "/groups"  // POST 創建群組
        /// POST /conversations/{id}/members 添加群組成員
        static func addGroupMembers(_ conversationId: String) -> String {
            "/conversations/\(conversationId)/members"
        }
        /// DELETE /conversations/{id}/members/{uid} 移除群組成員
        static func removeGroupMember(conversationId: String, userId: String) -> String {
            "/conversations/\(conversationId)/members/\(userId)"
        }
        /// PUT /conversations/{id}/members/{uid}/role 更新成員角色
        static func updateMemberRole(conversationId: String, userId: String) -> String {
            "/conversations/\(conversationId)/members/\(userId)/role"
        }

        // Voice/Video Calls
        /// POST /conversations/{id}/calls 發起通話
        static func initiateCall(_ conversationId: String) -> String {
            "/conversations/\(conversationId)/calls"
        }
        /// POST /calls/{id}/answer 接聽通話
        static func answerCall(_ callId: String) -> String { "/calls/\(callId)/answer" }
        /// POST /calls/{id}/reject 拒絕通話
        static func rejectCall(_ callId: String) -> String { "/calls/\(callId)/reject" }
        /// POST /calls/{id}/end 結束通話
        static func endCall(_ callId: String) -> String { "/calls/\(callId)/end" }
        /// POST /calls/ice-candidate 發送 ICE candidate
        static let sendIceCandidate = "/calls/ice-candidate"
        /// GET /calls/ice-servers 獲取 TURN/STUN 服務器配置
        static let getIceServers = "/calls/ice-servers"

        // Location Sharing
        /// POST /conversations/{id}/location 分享位置
        static func shareLocation(_ conversationId: String) -> String {
            "/conversations/\(conversationId)/location"
        }
        /// DELETE /conversations/{id}/location 停止分享位置
        static func stopSharingLocation(_ conversationId: String) -> String {
            "/conversations/\(conversationId)/location"
        }
        /// GET /nearby-users 獲取附近用戶
        static let getNearbyUsers = "/nearby-users"

        /// WebSocket 連接端點
        static let websocket = "/ws/chat"
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

    // MARK: - Search API
    struct Search {
        /// GET /api/v2/search - 通用搜索
        static let search = "/api/v2/search"
        static let searchAll = "/api/v2/search"  // Alias for SearchService
        /// GET /api/v2/search/users - 搜索用戶
        static let users = "/api/v2/search/users"
        static let searchUsers = "/api/v2/search/users"  // Alias for SearchService
        /// GET /api/v2/search/posts - 搜索貼文
        static let posts = "/api/v2/search/posts"
        static let searchContent = "/api/v2/search/posts"  // Alias for SearchService
        /// GET /api/v2/search/tags - 搜索標籤
        static let tags = "/api/v2/search/tags"
        static let searchHashtags = "/api/v2/search/tags"  // Alias for SearchService
        /// GET /api/v2/search/suggestions - 搜索建議
        static let suggestions = "/api/v2/search/suggestions"
        static let getSuggestions = "/api/v2/search/suggestions"  // Alias for SearchService
        /// GET /api/v2/search/trending - 熱門搜索
        static let trending = "/api/v2/search/trending"
        static let getTrending = "/api/v2/search/trending"  // Alias for SearchService
    }

    // MARK: - E2EE (End-to-End Encryption) API
    struct E2EE {
        /// POST /api/v2/e2ee/devices - Register device for E2EE
        static let registerDevice = "/api/v2/e2ee/devices"
        /// POST /api/v2/e2ee/keys/upload - Upload one-time prekeys
        static let uploadKeys = "/api/v2/e2ee/keys/upload"
        /// POST /api/v2/e2ee/keys/claim - Claim one-time keys from other devices
        static let claimKeys = "/api/v2/e2ee/keys/claim"
        /// POST /api/v2/e2ee/keys/query - Query device keys for users
        static let queryKeys = "/api/v2/e2ee/keys/query"
        /// GET /api/v2/e2ee/to-device - Get pending to-device messages
        static let toDeviceMessages = "/api/v2/e2ee/to-device"
        /// DELETE /api/v2/e2ee/to-device/{message_id} - Acknowledge to-device message
        static func ackToDeviceMessage(_ messageId: String) -> String {
            "/api/v2/e2ee/to-device/\(messageId)"
        }
        /// POST /api/v2/e2ee/messages - Send pre-encrypted E2EE message
        static let sendMessage = "/api/v2/e2ee/messages"
        /// GET /api/v2/e2ee/messages - Get E2EE messages for conversation
        static let getMessages = "/api/v2/e2ee/messages"
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
