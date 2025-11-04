# Nova 项目 - 后端架构与 iOS 连接分析

## 执行总结

这是一个**现代微服务架构**，采用 Rust + Actix-web 构建。当前处于**P1.2阶段**，正在从单体服务分离功能到专门的微服务。核心问题不在架构，而在于**iOS客户端与后端的网络配置和API契约对齐**。

---

## 一、后端服务架构概览

### 正在运行的主要服务（Docker Compose）

| 服务 | 端口 | 职责 | 状态 |
|-----|------|------|------|
| **user-service** | 8080 (内部) | 用户管理、个人资料、关注/粉丝 | ✅ 完整 |
| **auth-service** | 8084 (内部) | JWT 生成、OAuth、令牌验证 | ✅ 完整 |
| **content-service** | 8081 (内部) | 帖子 CRUD、评论、故事 | ✅ 骨架 |
| **feed-service** | 8082 (内部) | Feed 生成、排序、推荐 | ✅ 骨架 |
| **messaging-service** | 3000 (内部) | 消息、WebSocket、E2E 加密 | ✅ 完整 |
| **media-service** | - | S3 预签名 URL、图片上传 | ✅ 部分 |
| **nginx-gateway** | **3000** (外部) | API 网关、路由 | ✅ 运行中 |
| **PostgreSQL** | 5432 | 主数据库 | ✅ 运行中 |
| **Redis** | 6379 | 缓存、会话 | ✅ 运行中 |
| **ClickHouse** | 8123 | 分析、Feed 排序 | ✅ 运行中 |

### 重点：API 网关路由
```
iOS App → nginx-gateway (http://192.168.31.127:3000) 
         → 根据路径路由到内部服务
         → /api/v1/feed → feed-service:8082
         → /api/v1/posts → content-service:8081
         → /api/v1/users → user-service:8080
         → /ws → messaging-service:3000
```

---

## 二、数据库架构

### 核心表结构

#### 1. **posts** (帖子表) - 在 `003_posts_schema.sql`
```sql
CREATE TABLE posts (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL,
    caption TEXT,                  -- 最多 2200 字符
    image_key VARCHAR(512),        -- S3 对象键
    status VARCHAR(50),            -- pending | processing | published | failed
    created_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE,
    soft_delete TIMESTAMP WITH TIME ZONE  -- GDPR 合规
);

-- 关键索引
CREATE INDEX idx_posts_user_created ON posts(user_id, created_at DESC) 
    WHERE soft_delete IS NULL;
CREATE INDEX idx_posts_created_published ON posts(created_at DESC) 
    WHERE status = 'published' AND soft_delete IS NULL;
```

#### 2. **post_images** (转码的图片变体)
```sql
CREATE TABLE post_images (
    id UUID PRIMARY KEY,
    post_id UUID REFERENCES posts(id),
    s3_key VARCHAR(512),
    size_variant VARCHAR(50),  -- thumbnail | medium | original
    status VARCHAR(50),        -- pending | processing | completed | failed
    file_size INT,
    width INT, height INT,
    url VARCHAR(1024)
);
```

#### 3. **post_metadata** (参与统计)
```sql
CREATE TABLE post_metadata (
    post_id UUID PRIMARY KEY REFERENCES posts(id),
    like_count INT DEFAULT 0,
    comment_count INT DEFAULT 0,
    view_count INT DEFAULT 0,
    updated_at TIMESTAMP WITH TIME ZONE
);
```

#### 4. **users** (用户表) - 由 `user-service` 管理
- id (UUID)
- username, email, display_name
- profile_image_url, bio
- created_at, updated_at, deleted_at

---

## 三、API 端点详解

### 后端实现的路由

#### Content Service (`/api/v1/*`)

**帖子管理：**
```
POST   /api/v1/posts                    # 创建帖子
GET    /api/v1/posts/{post_id}          # 获取帖子详情
GET    /api/v1/posts/user/{user_id}     # 获取用户的帖子
PATCH  /api/v1/posts/{post_id}          # 更新帖子状态
DELETE /api/v1/posts/{post_id}          # 删除帖子
```

**故事 (Stories)：**
```
POST   /api/v1/stories                  # 创建故事
GET    /api/v1/stories/{story_id}       # 获取故事
GET    /api/v1/stories/user/{user_id}   # 获取用户故事
DELETE /api/v1/stories/{story_id}       # 删除故事
POST   /api/v1/stories/{story_id}/views # 追踪故事浏览
```

#### Feed Service (`/api/v1/feed/*`)

```
GET    /api/v1/feed                     # 获取个性化Feed
       查询参数:
       - cursor: Optional[String]        # 分页游标 (base64 编码)
       - limit: u32 (默认20, 最大100)
       - algo: String                   # "ch" (ClickHouse) 或 "time"
```

**响应示例：**
```json
{
  "posts": ["uuid1", "uuid2", ...],     # 帖子 ID 列表
  "cursor": "base64encoded_offset",      # 下一页游标
  "has_more": true
}
```

#### User Service (`/api/v1/users/*`)
```
GET    /api/v1/users/{user_id}          # 获取用户资料
PUT    /api/v1/users/{user_id}          # 更新用户资料
GET    /api/v1/users/{user_id}/followers
GET    /api/v1/users/{user_id}/following
POST   /api/v1/users/{user_id}/follow
DELETE /api/v1/users/{user_id}/follow
```

#### Auth Service (`/api/v1/auth/*`)
```
POST   /api/v1/auth/register            # 注册
POST   /api/v1/auth/login               # 登录
POST   /api/v1/auth/logout              # 登出
POST   /api/v1/auth/refresh             # 刷新令牌
GET    /api/v1/auth/verify              # 验证令牌
```

---

## 四、iOS 客户端网络配置分析

### 当前配置 (`AppConfig.swift`)

```swift
var baseURL: URL {
    switch Environment.current {
    case .development:
        #if targetEnvironment(simulator)
        // ✅ 正确：使用主机 IP 而不是 localhost
        return URL(string: "http://192.168.31.127:3000")!  // nginx 网关
        #else
        return URL(string: "http://localhost:8080")!       // 物理设备
        #endif
    case .staging:
        return URL(string: "https://api-staging.nova.social")!
    case .production:
        return URL(string: "https://api.nova.social")!
    }
}
```

**问题分析：**
- ✅ **模拟器配置正确** - 使用 `192.168.31.127:3000` 而非 localhost
- ⚠️ **物理设备配置** - 使用 `localhost:8080` 不会工作！应该改为主机 IP 或 VPN

### iOS API 客户端实现

#### APIClient (核心HTTP客户端)

```swift
final class APIClient {
    func request<T: Decodable>(
        _ endpoint: APIEndpoint,
        authenticated: Bool = true
    ) async throws -> T {
        let urlRequest = try buildRequest(endpoint, authenticated: authenticated)
        
        // 实现要点：
        // 1. 自动 Bearer token 注入
        // 2. JSON encoder/decoder（支持 snake_case）
        // 3. HTTP 错误处理 (200-299 为成功)
        // 4. 30 秒超时
    }
}
```

#### PostRepository (帖子业务逻辑)

```swift
final class PostRepository {
    func createPost(image: UIImage, caption: String?) async throws -> Post {
        // 流程：
        // 1️⃣ 压缩图片 (JPEG, 质量 0.8)
        // 2️⃣ 获取预签名 S3 URL
        // 3️⃣ 上传图片
        // 4️⃣ 创建帖子记录
        //   POST /api/v1/posts
        //   {
        //     "image_key": "s3_object_key",
        //     "caption": "optional text",
        //     "content_type": "image/jpeg"
        //   }
        // 5️⃣ 返回 Post 模型
    }
    
    func getPost(id: UUID) async throws -> Post {
        // GET /api/v1/posts/{id}
    }
    
    func likePost(id: UUID) async throws -> (liked: Bool, likeCount: Int) {
        // POST /api/v1/posts/{id}/like (带请求去重)
    }
    
    func deletePost(id: UUID) async throws {
        // DELETE /api/v1/posts/{id}
    }
}
```

#### FeedRepository (Feed 数据加载)

```swift
final class FeedRepository {
    func loadFeed(cursor: String? = nil, limit: Int = 20) async throws -> [Post] {
        // 流程：
        // 1. 检查本地缓存
        // 2. 如果没有，从网络加载：
        //   GET /api/v1/feed?cursor=...&limit=20&algo=ch
        // 3. 缓存结果
        // 4. 返回 Post 列表
    }
    
    func refreshFeed() async throws -> [Post] {
        // 清除缓存，强制从网络加载
    }
}
```

---

## 五、当前状态与连接流程

### ✅ 已实现

1. **数据库架构** - Posts、Images、Metadata 表已完全定义
2. **后端 API 路由** - Content-Service 和 Feed-Service 骨架就绪
3. **iOS 网络层** - APIClient、Repositories、AuthManager 已实现
4. **认证流程** - JWT token 管理和自动注入

### ⚠️ 缺失或需要完成

1. **Content-Service Handler 实现** - Posts CRUD 的完整业务逻辑
2. **Feed-Service 数据连接** - ClickHouse 查询集成
3. **Post 模型定义** - iOS 端的 Codable 结构（与后端响应匹配）
4. **Feed 分页实现** - Cursor 的完整处理
5. **图片转码管道** - S3 上传和缩略图生成

---

## 六、真实数据连接的需求

### 6.1 后端端点必须实现

```rust
// content-service/src/handlers/posts.rs

pub async fn create_post(
    pool: web::Data<PgPool>,
    user_id: UserId,
    req: web::Json<CreatePostRequest>,
) -> Result<HttpResponse> {
    // ✅ 插入 posts 表
    // ✅ 创建 post_metadata 记录（自动触发）
    // ✅ 返回 PostResponse { id, user_id, caption, image_key, ... }
}

pub async fn get_post(
    pool: web::Data<PgPool>,
    post_id: web::Path<Uuid>,
) -> Result<HttpResponse> {
    // ✅ 从 posts + post_images 连接查询
    // ✅ 返回完整 Post 对象（包括所有图片 URL）
}
```

### 6.2 iOS 端模型定义

```swift
struct Post: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let caption: String?
    let imageUrl: String              // 转码后的 medium 版本
    let thumbnailUrl: String
    let originalUrl: String
    let likeCount: Int
    let commentCount: Int
    let viewCount: Int
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id, caption, likeCount, viewCount, createdAt
        case userId = "user_id"
        case imageUrl = "image_url"
        case thumbnailUrl = "thumbnail_url"
        case originalUrl = "original_url"
        case commentCount = "comment_count"
    }
}
```

### 6.3 Feed 查询完整流程

**iOS 发送：**
```
GET /api/v1/feed?cursor=null&limit=20&algo=ch
Authorization: Bearer <jwt_token>
```

**后端处理：**
1. 从 ClickHouse 查询排序的 post_id 列表
2. 从 PostgreSQL 获取完整 Post 对象
3. 编码下一页 cursor

**iOS 接收：**
```json
{
  "posts": [
    {
      "id": "uuid1",
      "user_id": "user_uuid",
      "caption": "Beautiful sunset",
      "image_url": "https://cdn.nova.social/posts/uuid1/medium.jpg",
      "like_count": 42,
      "comment_count": 5,
      "created_at": "2025-11-03T10:30:00Z"
    }
  ],
  "cursor": "base64_offset",
  "has_more": true
}
```

---

## 七、关键技术细节

### 认证流程
```
1. iOS 调用 POST /api/v1/auth/login
2. 后端返回 { access_token, refresh_token, expires_in }
3. AuthManager 存储 token 到 Keychain
4. 所有后续请求自动在 Header 中注入：Authorization: Bearer <token>
5. Token 过期时，自动调用 /api/v1/auth/refresh
```

### 图片处理管道
```
iOS 上传：
  1. UIImage → 压缩 (JPEG 0.8) → 获取 S3 预签名 URL
  2. 直接上传到 S3
  3. 创建 posts 记录，状态为 "pending"

后端处理：
  4. 触发异步图片处理 Job
  5. 生成 thumbnail (150×150), medium (600×600), original (保留)
  6. 更新 post_images 表和 post.status = "published"

iOS 显示：
  7. Feed 返回 medium_url（为平衡大小和质量）
  8. 用户点击时加载 original_url
```

### 缓存策略
```
iOS 端：
  - Feed: 120秒 TTL（后台可刷新）
  - Post 详情: 300秒 TTL
  - 用户资料: 600秒 TTL

后端 Redis：
  - Feed 排序结果: 60秒
  - 热门帖子: 3600秒

ClickHouse：
  - 持久化 Feed 排序指标
  - 支持用户行为分析
```

---

## 八、部署和访问说明

### 本地开发环境

```bash
# 启动所有服务
docker-compose up -d

# 验证服务健康
curl http://192.168.31.127:3000/api/v1/health

# 查看 logs
docker logs -f nginx-gateway
docker logs -f content-service
docker logs -f feed-service
```

### iOS Simulator 配置

```swift
// 网络设置已正确：
// - Simulator: 192.168.31.127:3000 (nginx)
// - Device: <host_ip>:3000

// 需要在 Info.plist 配置：
<key>NSLocalNetworkUsageDescription</key>
<string>Used to connect to local development server</string>
<key>NSBonjourServices</key>
<array>
    <string>_http._tcp</string>
    <string>_ws._tcp</string>
</array>
```

---

## 九、常见问题排查

### 问题 1：iOS 连接超时
**现象：** `URLError.timedOut` 或 `NSURLErrorCannotConnectToHost`

**原因：**
- Simulator 使用错误的 IP（localhost instead of 192.168.31.127）
- Firewall 阻止 3000 端口
- nginx 网关未运行

**解决：**
```bash
# 检查 nginx
docker logs nginx-gateway | grep -i error

# 测试连接
curl -v http://192.168.31.127:3000/api/v1/health

# 更新 iOS AppConfig.swift
return URL(string: "http://192.168.31.127:3000")!
```

### 问题 2：401 Unauthorized
**原因：** JWT token 未正确注入或已过期

**检查：**
```swift
// AuthManager 中验证
if let token = AuthManager.shared.accessToken {
    print("Token: \(token)")  // 应该有值
} else {
    print("No token stored")  // 需要先登录
}
```

### 问题 3：Feed 返回空结果
**原因：** 
- ClickHouse 未初始化
- 数据库中无帖子
- User 不被跟踪

**检查：**
```bash
# 确认 posts 表有数据
curl -X GET "http://192.168.31.127:3000/api/v1/posts/user/{user_id}" \
  -H "Authorization: Bearer <token>"

# 检查 ClickHouse
docker exec clickhouse-server clickhouse-client \
  -q "SELECT COUNT(*) FROM nova.feed_posts"
```

---

## 十、下一步行动清单

### Phase 1：完成 Content-Service
- [ ] 实现 `create_post` 处理程序（插入 posts + post_metadata）
- [ ] 实现 `get_post` 处理程序（带图片 URL）
- [ ] 实现 `get_user_posts` 处理程序（分页）
- [ ] 实现 `delete_post` 处理程序
- [ ] 添加 PostService 业务逻辑类

### Phase 2：Feed 数据流
- [ ] 实现 Feed-Service 与 ClickHouse 集成
- [ ] 完成 Feed 排序算法
- [ ] 实现 Cursor 分页
- [ ] 添加 Fallback 查询（时间排序）

### Phase 3：iOS 完整集成
- [ ] 定义 Post 和 Feed 的 Codable 结构
- [ ] 测试 PostRepository 的所有方法
- [ ] 集成到 SwiftUI 视图（FeedView、PostDetailView）
- [ ] 实现离线模式和缓存

### Phase 4：验证
- [ ] 端到端测试（真实数据库）
- [ ] 性能测试（Feed 加载时间 < 2s）
- [ ] 网络错误恢复测试
- [ ] 设备和模拟器测试

---

## 总结

**优点：**
- ✅ 微服务架构清晰
- ✅ API 设计合理（分页、游标、算法选择）
- ✅ iOS 网络层完整（APIClient、认证、错误处理）
- ✅ 数据库模式完善（索引、触发器、GDPR）

**需要完成：**
- ⚠️ 后端业务逻辑实现（Content-Service）
- ⚠️ Feed 数据聚合（ClickHouse 集成）
- ⚠️ iOS 模型定义和视图集成

**预计工作量：**
- Content-Service 完成：2-3 天
- Feed Service 集成：3-5 天
- iOS 集成和测试：2-3 天
