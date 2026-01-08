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
            // Staging API via Cloudflare proxy with valid SSL
            // DNS: staging-api.icered.com -> Cloudflare (SSL termination) -> 34.8.163.8
            return "https://staging-api.icered.com"
        case .production:
            return "https://api.icered.com"
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
        return .staging  // Using staging API
        #else
        // TEMP: Using staging for TestFlight testing (production API not ready)
        // TODO: Change back to .production when production environment is ready
        return .staging
        #endif
    }()

    // MARK: - Endpoints

    struct Graph {
        static let followers = "/api/v2/graph/followers"
        static let following = "/api/v2/graph/following"
        static let follow = "/api/v2/graph/follow"
        // unfollow uses DELETE /api/v2/graph/follow/{user_id}
        static func unfollow(_ userId: String) -> String { "/api/v2/graph/follow/\(userId)" }
        // isFollowing uses GET /api/v2/graph/is-following/{user_id}
        static func isFollowing(_ userId: String) -> String { "/api/v2/graph/is-following/\(userId)" }
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
        static let getLikes = "/api/v2/social/likes"
        static let checkLiked = "/api/v2/social/check-liked"
        /// POST /api/v2/social/batch-check-liked - 批量檢查帖子點讚狀態（修復刷新後狀態不一致）
        static let batchCheckLiked = "/api/v2/social/batch-check-liked"
        /// GET /api/v2/social/users/{user_id}/liked-posts 獲取用戶點讚的帖子
        static func getUserLikedPosts(_ userId: String) -> String { "/api/v2/social/users/\(userId)/liked-posts" }
        static let createComment = "/api/v2/social/comment"
        static let deleteComment = "/api/v2/social/comment"  // comment_id goes in body
        static let getComments = "/api/v2/social/comments"

        // Comment Like endpoints (IG/小红书风格评论点赞)
        static let createCommentLike = "/api/v2/social/comment/like"
        static func deleteCommentLike(_ commentId: String) -> String { "/api/v2/social/comment/unlike/\(commentId)" }
        static func getCommentLikes(_ commentId: String) -> String { "/api/v2/social/comment/likes/\(commentId)" }
        static func checkCommentLiked(_ commentId: String) -> String { "/api/v2/social/comment/check-liked/\(commentId)" }
        /// POST /api/v2/social/comment/batch-check-liked - 批量檢查評論按讚狀態（修復 N+1 問題）
        static let batchCheckCommentLiked = "/api/v2/social/comment/batch-check-liked"
        static let createShare = "/api/v2/social/share"
        static func getShareCount(_ postId: String) -> String { "/api/v2/social/shares/count/\(postId)" }
        static let batchGetStats = "/api/v2/social/stats/batch"

        // Save/Bookmark endpoints
        // Write operations use /save (verb), read operations use /saved-posts (resource)
        static let createBookmark = "/api/v2/social/save"
        static func deleteBookmark(_ postId: String) -> String { "/api/v2/social/save/\(postId)" }
        static let getBookmarks = "/api/v2/social/saved-posts"
        static func checkBookmarked(_ postId: String) -> String { "/api/v2/social/saved-posts/\(postId)/check" }
        static let batchCheckBookmarked = "/api/v2/social/saved-posts/batch-check"
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
        /// POST /api/v1/posts/batch - Batch fetch posts by IDs (single request)
        static let batchPosts = "/api/v1/posts/batch"
        /// GET /api/v2/content/user/{user_id}/liked - Get posts liked by user (SQL JOIN)
        static func userLikedPosts(_ userId: String) -> String { "/api/v2/content/user/\(userId)/liked" }
        /// GET /api/v2/content/user/{user_id}/saved - Get posts saved by user (SQL JOIN)
        static func userSavedPosts(_ userId: String) -> String { "/api/v2/content/user/\(userId)/saved" }
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
        // 輕量級上傳初始化端點：只發送元數據，獲取 presigned URL
        static let uploadInitiate = "/api/v2/media/upload/initiate"
        // 舊的多部分上傳端點（保留向後兼容）
        static let uploadStart = "/api/v2/media/upload"
        static let uploadProgress = "/api/v2/media/upload"
        // 完成上傳端點：需要 upload_id 作為路徑參數
        static func uploadComplete(_ uploadId: String) -> String {
            "/api/v2/media/upload/\(uploadId)/complete"
        }
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
        static let requestPasswordReset = "/api/v2/auth/password/reset/request"
        static let resetPassword = "/api/v2/auth/password/reset"

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
        static let enhancePost = "/api/v2/alice/enhance"  // POST 圖片分析與內容建議
    }

    // MARK: - VLM (Vision Language Model) API
    struct VLM {
        /// POST /api/v2/vlm/analyze - 分析圖片並獲取標籤和頻道建議
        static let analyze = "/api/v2/vlm/analyze"
        /// GET /api/v2/posts/{id}/tags - 獲取帖子的標籤
        static func getPostTags(_ postId: String) -> String { "/api/v2/posts/\(postId)/tags" }
        /// PUT /api/v2/posts/{id}/tags - 更新帖子標籤和頻道
        static func updatePostTags(_ postId: String) -> String { "/api/v2/posts/\(postId)/tags" }
    }

    // MARK: - X.AI (Grok) API Proxy
    /// Grok chat requests are proxied through our backend to protect API keys
    struct XAI {
        /// GET /api/v2/xai/status - 獲取 X.AI 服務狀態
        static let status = "/api/v2/xai/status"
        /// POST /api/v2/xai/chat - 發送聊天消息到 Grok
        static let chat = "/api/v2/xai/chat"
        /// POST /api/v2/xai/chat/stream - 串流聊天 (SSE)
        static let chatStream = "/api/v2/xai/chat/stream"
        /// POST /api/v2/xai/voice/token - 獲取語音 WebSocket 臨時 token
        static let voiceToken = "/api/v2/xai/voice/token"
    }

    // MARK: - LiveKit Voice Agent API
    /// LiveKit-based voice agent for reliable barge-in support
    struct LiveKit {
        /// POST /api/v2/livekit/token - 獲取 LiveKit access token
        static let token = "/api/v2/livekit/token"
    }

    // MARK: - Alice Voice Service API (TEN Agent)
    struct AliceVoice {
        /// TEN Agent 服務器基礎 URL
        /// Note: Uses URL rewriting via GCE URL Map routeRules
        /// Staging: Uses main API gateway with /alice-voice path prefix
        /// Production: https://api.nova.social/alice-voice
        static var baseURL: String {
            switch current {
            case .development:
                if let localURL = ProcessInfo.processInfo.environment["ALICE_VOICE_URL"] {
                    return localURL
                }
                return "http://localhost:8080"
            case .staging:
                // Route through main API gateway with URL rewriting
                return "\(current.baseURL)/alice-voice"
            case .production:
                return "https://api.nova.social/alice-voice"
            }
        }

        /// POST /start - 啟動 TEN Agent 會話
        static var start: String { "\(baseURL)/start" }
        /// POST /stop - 停止 TEN Agent 會話
        static var stop: String { "\(baseURL)/stop" }
        /// POST /ping - Keep-alive for TEN Agent 會話
        static var ping: String { "\(baseURL)/ping" }
        /// GET /health - 健康檢查
        static var health: String { "\(baseURL)/health" }
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
        /// POST /api/v2/auth/users/profiles/batch 批量獲取用戶資料
        static let batchGetProfiles = "/api/v2/auth/users/profiles/batch"
    }

    // MARK: - User Profile Data API (ranking-service via graphql-gateway)
    struct UserProfile {
        /// POST /api/v2/photo-analysis/upload - 上傳照片分析結果
        /// Used by iOS Vision photo library analysis for interest building
        static let uploadPhotoAnalysis = "/api/v2/photo-analysis/upload"
        /// POST /api/v2/photo-analysis/onboarding - 上傳 Onboarding 選擇的興趣
        static let uploadOnboardingInterests = "/api/v2/photo-analysis/onboarding"
        /// GET /api/v2/profile/interests - 獲取用戶興趣標籤
        static let getInterests = "/api/v2/profile/interests"
    }

    // MARK: - User Settings API (identity-service - SINGLE SOURCE OF TRUTH)
    struct Settings {
        /// GET /api/v2/auth/users/{id}/settings 獲取用戶設定
        /// NOTE: identity-service is the SINGLE SOURCE OF TRUTH for all user settings
        /// including dm_permission (P0 migration completed).
        /// Do NOT use Relationships.getPrivacySettings - it is deprecated.
        static func getSettings(_ userId: String) -> String { "/api/v2/auth/users/\(userId)/settings" }
        /// PUT /api/v2/auth/users/{id}/settings 更新用戶設定
        /// NOTE: identity-service is the SINGLE SOURCE OF TRUTH.
        /// Use this endpoint for all settings updates including dm_permission.
        static func updateSettings(_ userId: String) -> String { "/api/v2/auth/users/\(userId)/settings" }
    }

    // MARK: - Friends & Social Graph API
    struct Friends {
        static let searchUsers = "/api/v2/search/users"  // GET 搜索用戶 ?q={query}
        static let getRecommendations = "/api/v2/friends/recommendations"  // GET 獲取推薦聯絡人
        static let addFriend = "/api/v2/friends/add"  // POST 添加好友 (直接添加，無需確認)
        static let removeFriend = "/api/v2/friends/remove"  // DELETE 移除好友
        static let getFriendsList = "/api/v2/friends/list"  // GET 獲取好友列表

        // MARK: - Friend Request Management
        static let sendRequest = "/api/v2/friends/request"  // POST 發送好友請求
        static let getPendingRequests = "/api/v2/friends/requests"  // GET 待處理請求 ?type=received|sent
        static let acceptRequest = "/api/v2/friends/request/accept"  // POST 接受請求
        static let rejectRequest = "/api/v2/friends/request/reject"  // POST 拒絕請求
        static func cancelRequest(_ requestId: String) -> String {  // DELETE 取消已發送的請求
            "/api/v2/friends/request/\(requestId)"
        }
        static let pendingCount = "/api/v2/friends/requests/count"  // GET 待處理請求數量
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
        /// POST /api/v2/channels/suggest AI-powered channel suggestions
        static let suggestChannels = "/api/v2/channels/suggest"
    }

    // MARK: - Account Management API
    struct Accounts {
        static let getAccounts = "/api/v2/accounts"  // GET 獲取用戶所有帳戶
        static let switchAccount = "/api/v2/accounts/switch"  // POST 切換帳戶
        static let removeAccount = "/api/v2/accounts"  // DELETE /api/v2/accounts/{id} 刪除帳戶

        // Alias account endpoints
        static let createAlias = "/api/v2/accounts/alias"  // POST 創建別名帳戶
        static let updateAlias = "/api/v2/accounts/alias"  // PUT /api/v2/accounts/alias/{id} 更新別名帳戶
        static let getAlias = "/api/v2/accounts/alias"  // GET /api/v2/accounts/alias/{id} 獲取別名帳戶
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
        // Waitlist - 收集無邀請碼用戶的郵箱 (無需認證)
        static let waitlist = "/api/v2/auth/waitlist"  // POST {email: string}
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

    // MARK: - Trending API
    struct Trending {
        /// GET /api/v2/trending - Get trending content
        static let getTrending = "/api/v2/trending"
        /// GET /api/v2/trending/videos - Get trending videos
        static let getVideos = "/api/v2/trending/videos"
        /// GET /api/v2/trending/posts - Get trending posts
        static let getPosts = "/api/v2/trending/posts"
        /// GET /api/v2/trending/streams - Get trending streams
        static let getStreams = "/api/v2/trending/streams"
        /// GET /api/v2/trending/categories - Get trending categories
        static let getCategories = "/api/v2/trending/categories"
        /// POST /api/v2/trending/engagement - Record engagement
        static let recordEngagement = "/api/v2/trending/engagement"
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

        // Message Search
        /// GET /api/v2/chat/messages/search 搜尋訊息
        /// Query params: conversation_id (optional), query, limit, offset
        static let searchMessages = "/api/v2/chat/messages/search"

        // Message Pinning
        /// POST /api/v2/chat/messages/{id}/pin 釘選訊息
        static func pinMessage(_ messageId: String) -> String { "/api/v2/chat/messages/\(messageId)/pin" }
        /// DELETE /api/v2/chat/messages/{id}/pin 取消釘選
        static func unpinMessage(_ messageId: String) -> String { "/api/v2/chat/messages/\(messageId)/pin" }
        /// GET /api/v2/chat/conversations/{id}/pinned 獲取釘選的訊息
        static func getPinnedMessages(_ conversationId: String) -> String { "/api/v2/chat/conversations/\(conversationId)/pinned" }

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
        // ⚠️ DEPRECATED: Use APIConfig.Settings.getSettings/updateSettings instead
        // dm_permission is now managed by identity-service (SINGLE SOURCE OF TRUTH)
        // These endpoints will be removed in a future version
        @available(*, deprecated, message: "Use APIConfig.Settings.getSettings instead. dm_permission is now in identity-service.")
        static let getPrivacySettings = "/api/v2/settings/privacy"
        @available(*, deprecated, message: "Use APIConfig.Settings.updateSettings instead. dm_permission is now in identity-service.")
        static let updatePrivacySettings = "/api/v2/settings/privacy"

        // Message Requests (when dm_permission restricts non-followers)
        static let getMessageRequests = "/api/v2/message-requests"  // GET 獲取待處理的訊息請求
        /// POST /api/v2/message-requests/{id}/accept 接受訊息請求
        static func acceptMessageRequest(_ requestId: String) -> String { "/api/v2/message-requests/\(requestId)/accept" }
        /// POST /api/v2/message-requests/{id}/reject 拒絕訊息請求
        static func rejectMessageRequest(_ requestId: String) -> String { "/api/v2/message-requests/\(requestId)/reject" }

        // Report Management
        /// POST /api/v2/reports 舉報用戶或內容
        static let report = "/api/v2/reports"
        /// GET /api/v2/reports 獲取自己的舉報列表
        static let getReports = "/api/v2/reports"
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

    // MARK: - Matrix E2EE Integration API
    struct Matrix {
        /// POST /api/v2/matrix/token - Get device-bound Matrix access token for current user
        /// Request body: { "device_id": "NOVA_IOS_XXXX" }
        /// Response: { "access_token", "matrix_user_id", "device_id", "homeserver_url" }
        /// Backend generates device-bound tokens via Synapse Admin API (device_id param in Synapse 1.81+)
        static let getToken = "/api/v2/matrix/token"
        /// GET /api/v2/matrix/rooms - Get all conversation-to-room mappings for current user
        static let getRoomMappings = "/api/v2/matrix/rooms"
        /// POST /api/v2/matrix/rooms - Save a new conversation-to-room mapping
        static let saveRoomMapping = "/api/v2/matrix/rooms"
        /// GET /api/v2/matrix/rooms/{conversation_id} - Get room ID for a conversation
        static func getRoomMapping(_ conversationId: String) -> String {
            "/api/v2/matrix/rooms/\(conversationId)"
        }
        /// GET /api/v2/matrix/conversations - Get conversation ID for a room (query: room_id)
        static let getConversationMapping = "/api/v2/matrix/conversations"
        /// GET /api/v2/matrix/config - Get Matrix homeserver configuration
        static let getConfig = "/api/v2/matrix/config"
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

    // MARK: - Analytics API (推薦系統信號)
    struct Analytics {
        /// POST /api/v2/analytics/watch-events - 批量上報觀看事件
        static let recordWatchEvents = "/api/v2/analytics/watch-events"
        /// POST /api/v2/analytics/engagement - 上報互動信號
        static let recordEngagement = "/api/v2/analytics/engagement"
        /// POST /api/v2/analytics/negative-signal - 上報負面信號
        static let recordNegativeSignal = "/api/v2/analytics/negative-signal"
        /// POST /api/v2/analytics/session - 上報會話數據
        static let recordSession = "/api/v2/analytics/session"
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
    /// Allow connecting to staging even if the TLS cert does not match (DEBUG only).
    /// Keep this false for release builds.
    static var allowInsecureStagingCert = true
    /// Enable SSL certificate pinning for enhanced security.
    /// When enabled, connections will only succeed if the server certificate matches
    /// the pinned public key hashes in CertificatePinningManager.
    /// Note: Update pinned hashes in CertificatePinningManager before enabling in production.
    static var enableCertificatePinning = false
}
