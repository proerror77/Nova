# NovaInstagram iOS 后端集成完整方案

## 📋 架构概述

本文档定义 NovaInstagram iOS 应用与 Rust 后端的完整集成方案，包括 API 设计、认证系统、数据同步和 Swift 实现代码。

### 设计原则

1. **简洁至上** - 3 层架构：APIClient → Repository → LocalStorage
2. **零破坏性** - Token 刷新、离线模式自动处理，对业务代码透明
3. **系统优先** - URLSession、Codable、async/await，避免第三方依赖
4. **错误清晰** - 3 类错误：网络错误、业务错误、未知错误

---

## 🏗️ 系统架构

```
┌─────────────────────────────────────────────────────┐
│              SwiftUI Views (Presentation)            │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│         ViewModels (State Management)                │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│    Repository Layer (Business Logic + Cache)         │
│  - FeedRepository                                    │
│  - UserRepository                                    │
│  - PostRepository                                    │
│  - NotificationRepository                            │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│       APIClient (HTTP + Auth Interceptor)            │
│  - Request Building                                  │
│  - Token Management                                  │
│  - Retry Logic                                       │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│    Local Storage (Offline Support)                   │
│  - UserDefaults (Settings)                           │
│  - CoreData (Posts, Users, Feed Cache)               │
│  - FileManager (Images)                              │
└─────────────────────────────────────────────────────┘
```

---

## 🔐 认证系统设计

### JWT Token 方案

**Token 结构**:
```json
{
  "access_token": "eyJhbGc...",  // 15分钟有效期
  "refresh_token": "dGhpc2lz...", // 7天有效期
  "expires_in": 900,              // 秒
  "token_type": "Bearer"
}
```

**刷新流程** (自动化):
```
1. API 请求携带 Access Token
2. 后端返回 401 (Token Expired)
3. APIClient 自动拦截 401
4. 使用 Refresh Token 请求新 Access Token
5. 更新 Keychain 中的 Token
6. 重试原始请求（用户无感知）
7. 如果 Refresh Token 也过期 → 清空状态并跳转登录页
```

**安全存储**:
- Access Token + Refresh Token 存储在 **Keychain** (不使用 UserDefaults)
- 用户 ID、用户名等非敏感数据存储在 UserDefaults
- 使用 `kSecAttrAccessibleAfterFirstUnlock` 确保设备重启后可访问

---

## 📡 API 端点定义

### Base URL
```
Production: https://api.nova.social
Staging:    https://api-staging.nova.social
Local Dev:  http://localhost:8080
```

### 核心端点

#### 1. 认证 API
```
POST /auth/register
  Request:  { email, password, username }
  Response: { user: User, tokens: AuthTokens }

POST /auth/login
  Request:  { email, password }
  Response: { user: User, tokens: AuthTokens }

POST /auth/refresh
  Request:  { refresh_token }
  Response: { access_token, expires_in }

POST /auth/logout
  Request:  (Access Token in Header)
  Response: 204 No Content

POST /auth/verify-email
  Request:  { code }
  Response: { verified: true }
```

#### 2. Feed API
```
GET /feed
  Query:    ?cursor=<timestamp>&limit=20
  Response: { posts: [Post], next_cursor: String? }

GET /feed/explore
  Query:    ?page=1&limit=30
  Response: { posts: [Post], has_more: Bool }
```

#### 3. Post API
```
POST /posts/upload-url
  Request:  { content_type: "image/jpeg" }
  Response: { upload_url, file_key, expires_in }

POST /posts
  Request:  { file_key, caption? }
  Response: { post: Post }

GET /posts/{id}
  Response: { post: Post }

DELETE /posts/{id}
  Response: 204 No Content

POST /posts/{id}/like
  Response: { liked: true, like_count: Int }

DELETE /posts/{id}/like
  Response: { liked: false, like_count: Int }
```

#### 4. Comment API
```
GET /posts/{id}/comments
  Query:    ?cursor=<id>&limit=20
  Response: { comments: [Comment], next_cursor: String? }

POST /posts/{id}/comments
  Request:  { text }
  Response: { comment: Comment }

DELETE /comments/{id}
  Response: 204 No Content
```

#### 5. User API
```
GET /users/{username}
  Response: { user: User, stats: UserStats }

GET /users/{id}/posts
  Query:    ?cursor=<timestamp>&limit=20
  Response: { posts: [Post], next_cursor: String? }

PUT /users/me
  Request:  { bio?, avatar_url?, display_name? }
  Response: { user: User }

GET /users/search
  Query:    ?q=<query>&limit=20
  Response: { users: [User] }
```

#### 6. Follow API
```
POST /users/{id}/follow
  Response: { following: true, follower_count: Int }

DELETE /users/{id}/follow
  Response: { following: false, follower_count: Int }

GET /users/{id}/followers
  Query:    ?cursor=<id>&limit=20
  Response: { users: [User], next_cursor: String? }

GET /users/{id}/following
  Query:    ?cursor=<id>&limit=20
  Response: { users: [User], next_cursor: String? }
```

#### 7. Notification API
```
GET /notifications
  Query:    ?cursor=<id>&limit=20
  Response: { notifications: [Notification], next_cursor: String?, unread_count: Int }

PUT /notifications/{id}/read
  Response: 204 No Content

PUT /notifications/read-all
  Response: 204 No Content
```

---

## 📦 数据模型 (Codable)

### Core Models

```swift
// MARK: - Authentication
struct AuthTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

struct User: Codable, Identifiable {
    let id: UUID
    let username: String
    let email: String
    let displayName: String?
    let bio: String?
    let avatarUrl: String?
    let isVerified: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, username, email, bio
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case isVerified = "is_verified"
        case createdAt = "created_at"
    }
}

// MARK: - Post
struct Post: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let imageUrl: String
    let thumbnailUrl: String?
    let caption: String?
    let likeCount: Int
    let commentCount: Int
    let isLiked: Bool
    let createdAt: Date
    let user: User?

    enum CodingKeys: String, CodingKey {
        case id, caption
        case userId = "user_id"
        case imageUrl = "image_url"
        case thumbnailUrl = "thumbnail_url"
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case isLiked = "is_liked"
        case createdAt = "created_at"
        case user
    }
}

// MARK: - Comment
struct Comment: Codable, Identifiable {
    let id: UUID
    let postId: UUID
    let userId: UUID
    let text: String
    let createdAt: Date
    let user: User?

    enum CodingKeys: String, CodingKey {
        case id, text, user
        case postId = "post_id"
        case userId = "user_id"
        case createdAt = "created_at"
    }
}

// MARK: - Notification
enum NotificationType: String, Codable {
    case like, comment, follow, mention
}

struct Notification: Codable, Identifiable {
    let id: UUID
    let type: NotificationType
    let actorId: UUID
    let postId: UUID?
    let isRead: Bool
    let createdAt: Date
    let actor: User?
    let post: Post?

    enum CodingKeys: String, CodingKey {
        case id, type
        case actorId = "actor_id"
        case postId = "post_id"
        case isRead = "is_read"
        case createdAt = "created_at"
        case actor, post
    }
}

// MARK: - Feed Response
struct FeedResponse: Codable {
    let posts: [Post]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case posts
        case nextCursor = "next_cursor"
    }
}

// MARK: - User Stats
struct UserStats: Codable {
    let postCount: Int
    let followerCount: Int
    let followingCount: Int
    let isFollowing: Bool

    enum CodingKeys: String, CodingKey {
        case postCount = "post_count"
        case followerCount = "follower_count"
        case followingCount = "following_count"
        case isFollowing = "is_following"
    }
}
```

---

## 🚨 错误处理规范

### 错误类型定义

```swift
enum APIError: Error, LocalizedError {
    // 网络层错误
    case networkError(Error)
    case noConnection
    case timeout
    case cancelled

    // HTTP 错误
    case unauthorized         // 401
    case forbidden            // 403
    case notFound             // 404
    case conflict             // 409
    case serverError          // 500+

    // 业务错误
    case invalidCredentials
    case emailAlreadyExists
    case usernameAlreadyExists
    case invalidFileFormat
    case fileTooLarge
    case captionTooLong
    case rateLimitExceeded

    // 解析错误
    case decodingError(Error)
    case invalidResponse

    // 未知错误
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .networkError:
            return "网络连接失败，请检查网络设置"
        case .noConnection:
            return "无网络连接，请检查网络后重试"
        case .timeout:
            return "请求超时，请稍后重试"
        case .cancelled:
            return nil // 用户主动取消，不显示错误
        case .unauthorized:
            return "登录已过期，请重新登录"
        case .forbidden:
            return "没有权限执行此操作"
        case .notFound:
            return "请求的内容不存在"
        case .conflict:
            return "操作冲突，请刷新后重试"
        case .serverError:
            return "服务器错误，请稍后重试"
        case .invalidCredentials:
            return "邮箱或密码错误"
        case .emailAlreadyExists:
            return "该邮箱已被注册"
        case .usernameAlreadyExists:
            return "用户名已被占用"
        case .invalidFileFormat:
            return "不支持的文件格式，请选择 JPG 或 PNG"
        case .fileTooLarge:
            return "文件大小超过限制（最大 10MB）"
        case .captionTooLong:
            return "描述文字过长（最多 300 字符）"
        case .rateLimitExceeded:
            return "操作过于频繁，请稍后再试"
        case .decodingError:
            return "数据解析失败"
        case .invalidResponse:
            return "服务器响应格式错误"
        case .unknown(let message):
            return message.isEmpty ? "未知错误" : message
        }
    }
}
```

### HTTP 状态码映射

```swift
extension APIError {
    static func from(statusCode: Int, data: Data?) -> APIError {
        // 尝试解析后端返回的错误信息
        if let data = data,
           let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            return mapBackendError(errorResponse)
        }

        // 根据状态码返回通用错误
        switch statusCode {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 409: return .conflict
        case 429: return .rateLimitExceeded
        case 500...: return .serverError
        default: return .unknown("HTTP \(statusCode)")
        }
    }

    private static func mapBackendError(_ response: ErrorResponse) -> APIError {
        switch response.code {
        case "INVALID_CREDENTIALS": return .invalidCredentials
        case "EMAIL_EXISTS": return .emailAlreadyExists
        case "USERNAME_EXISTS": return .usernameAlreadyExists
        case "FILE_TOO_LARGE": return .fileTooLarge
        case "INVALID_FORMAT": return .invalidFileFormat
        case "CAPTION_TOO_LONG": return .captionTooLong
        default: return .unknown(response.message)
        }
    }
}

struct ErrorResponse: Codable {
    let code: String
    let message: String
}
```

---

## 🔄 数据同步策略

### 缓存策略

| 数据类型 | 策略 | 过期时间 | 离线可用 |
|---------|------|---------|---------|
| 用户资料 | Cache-First | 5分钟 | ✅ |
| Feed 数据 | Network-First | 30秒 | ✅ (最近50条) |
| Post 详情 | Cache-First | 1分钟 | ✅ |
| 通知 | Network-Only | - | ❌ |
| 搜索结果 | Network-Only | - | ❌ |

### 离线支持规则

1. **读取操作**: 优先返回缓存数据，后台刷新最新数据
2. **写入操作**: 无网络时保存到本地队列，网络恢复后自动同步
3. **冲突解决**: 客户端时间戳 + 服务端最终决定

### 数据版本控制

```swift
struct CachedData<T: Codable>: Codable {
    let data: T
    let cachedAt: Date
    let version: Int // API 版本号

    var isExpired: Bool {
        Date().timeIntervalSince(cachedAt) > expirationInterval
    }

    var expirationInterval: TimeInterval {
        // 根据数据类型返回不同的过期时间
        return 300 // 默认 5 分钟
    }
}
```

---

## 📡 网络层实现 (APIClient)

完整的 Swift 实现代码请参考以下文件：
- `APIClient.swift` - 核心 HTTP 客户端
- `AuthManager.swift` - 认证管理器
- `RequestInterceptor.swift` - 请求拦截器
- `RetryPolicy.swift` - 重试策略
- `Repositories/` - Repository 层实现

---

## 🔧 配置管理

### Environment Configuration

```swift
enum Environment {
    case development
    case staging
    case production

    var baseURL: URL {
        switch self {
        case .development: return URL(string: "http://localhost:8080")!
        case .staging: return URL(string: "https://api-staging.nova.social")!
        case .production: return URL(string: "https://api.nova.social")!
        }
    }

    var timeout: TimeInterval {
        return 30 // 30 seconds
    }
}
```

### Feature Flags

```swift
struct FeatureFlags {
    static let enableOfflineMode = true
    static let enableBackgroundUpload = true
    static let enableImageCompression = true
    static let maxRetryAttempts = 3
    static let feedPageSize = 20
    static let imageCacheSize = 100 * 1024 * 1024 // 100MB
}
```

---

## 📊 监控与日志

### 日志级别

```swift
enum LogLevel: String {
    case debug = "🔍 DEBUG"
    case info = "ℹ️ INFO"
    case warning = "⚠️ WARNING"
    case error = "❌ ERROR"
}

struct Logger {
    static func log(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        let filename = (file as NSString).lastPathComponent
        print("\(level.rawValue) [\(filename):\(line)] \(function) - \(message)")
        #endif
    }
}
```

### 性能监控

```swift
struct PerformanceMetrics {
    static func trackAPICall(endpoint: String, duration: TimeInterval, statusCode: Int) {
        // 集成第三方 APM (Firebase, DataDog, etc.)
        print("API Call: \(endpoint) | Duration: \(duration)s | Status: \(statusCode)")
    }
}
```

---

## 🚀 使用示例

### 1. 用户登录

```swift
let authRepo = AuthRepository()
do {
    let (user, tokens) = try await authRepo.login(email: "user@example.com", password: "password")
    print("登录成功: \(user.username)")
} catch let error as APIError {
    print("登录失败: \(error.localizedDescription)")
}
```

### 2. 加载 Feed

```swift
let feedRepo = FeedRepository()
Task {
    do {
        let posts = try await feedRepo.loadFeed(cursor: nil, limit: 20)
        print("加载了 \(posts.count) 条帖子")
    } catch {
        print("加载失败: \(error.localizedDescription)")
    }
}
```

### 3. 发布帖子

```swift
let postRepo = PostRepository()
Task {
    do {
        let post = try await postRepo.createPost(
            image: selectedImage,
            caption: "My first post!"
        )
        print("发布成功，Post ID: \(post.id)")
    } catch {
        print("发布失败: \(error.localizedDescription)")
    }
}
```

---

## ✅ 测试策略

### 单元测试覆盖

- APIClient HTTP 请求构建和解析
- Token 刷新逻辑
- 错误处理映射
- Repository 层业务逻辑

### 集成测试覆盖

- 完整的认证流程 (注册 → 登录 → Token 刷新)
- Feed 分页加载
- 图片上传流程
- 离线模式数据同步

### UI 测试覆盖

- 登录页面交互
- Feed 滚动加载
- 发布帖子流程
- 错误提示显示

---

## 📚 下一步

1. ✅ 阅读本文档理解架构
2. 📝 查看 Swift 代码实现 (`/ios/NovaSocial/Network/`)
3. 🧪 运行单元测试验证集成
4. 🚀 开始前端 UI 开发

---

**文档版本**: 1.0
**最后更新**: 2025-10-19
**维护者**: Backend Architecture Team
