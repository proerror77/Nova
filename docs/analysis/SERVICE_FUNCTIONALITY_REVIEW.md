# Nova 微服务功能审查报告

## 目录
1. [服务清单总览](#服务清单总览)
2. [核心服务详细审查](#核心服务详细审查)
3. [功能重叠分析](#功能重叠分析)
4. [缺失功能识别](#缺失功能识别)
5. [架构建议](#架构建议)

---

## 服务清单总览

### 当前部署状态 (Staging)

| # | 服务名称 | 状态 | 副本数 | 端口 | 依赖基础设施 |
|---|---------|------|-------|------|------------|
| 1 | identity-service | ✅ 运行中 | 1 | 50051 (gRPC) | Postgres |
| 2 | content-service | ✅ 运行中 | 1 | 50052 (gRPC) | Postgres |
| 3 | media-service | ✅ 运行中 | 1 | 50053 (gRPC) | Postgres + S3 |
| 4 | messaging-service | ✅ 运行中 | 1 | 50054 (gRPC) | Postgres |
| 5 | search-service | ✅ 运行中 | 1 | 8086 (HTTP) | Postgres + Elasticsearch |
| 6 | notification-service | ✅ 运行中 | 1 | 50056 (gRPC) | Redis |
| 7 | graphql-gateway | ⏸️ 禁用 | 0 | 8080 (HTTP) | All Services |
| 8 | feed-service | ⏸️ 禁用 | 0 | 50057 (gRPC) | Redis + Kafka |
| 9 | social-service | ⏸️ 禁用 | 0 | 50058 (gRPC) | Postgres |
| 10 | graph-service | ⏸️ 禁用 | 0 | 50059 (gRPC) | Neo4j |
| 11 | analytics-service | ⏸️ 禁用 | 0 | 50060 (gRPC) | Kafka + ClickHouse |
| 12 | ranking-service | ⏸️ 禁用 | 0 | 50061 (gRPC) | Redis + Postgres |
| 13 | realtime-chat-service | ⏸️ 禁用 | 0 | 50062 (gRPC+WS) | Redis + Kafka |
| 14 | trust-safety-service | ⏸️ 禁用 | 0 | 50063 (gRPC) | Postgres + Kafka |
| 15 | communication-service | ❓ 未确认 | ? | 50055 (gRPC) | Postgres |

**总结:**
- ✅ **6 个服务运行中** (核心路径)
- ⏸️ **8 个服务禁用** (资源优化)
- ❓ **1 个服务状态未知** (可能重复)

---

## 核心服务详细审查

### 1. identity-service (用户身份与认证)

**核心职责:**
- ✅ 用户注册、登录、登出
- ✅ JWT Token 签发与验证
- ✅ 密码哈希与验证 (Argon2)
- ✅ Session 管理
- ✅ OAuth2/OIDC 集成 (Google, GitHub, etc.)
- ✅ 用户资料基础信息 (username, email, avatar)

**API 示例:**
```protobuf
service IdentityService {
  rpc Register(RegisterRequest) returns (RegisterResponse);
  rpc Login(LoginRequest) returns (LoginResponse);
  rpc VerifyToken(VerifyTokenRequest) returns (VerifyTokenResponse);
  rpc RefreshToken(RefreshTokenRequest) returns (RefreshTokenResponse);
  rpc GetUserProfile(GetUserProfileRequest) returns (UserProfile);
}
```

**数据库 Schema:**
```sql
CREATE TABLE users (
  id UUID PRIMARY KEY,
  username VARCHAR(50) UNIQUE NOT NULL,
  email VARCHAR(255) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  avatar_url TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE sessions (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES users(id),
  token_hash VARCHAR(255) NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL
);
```

**事件发布:**
```
Kafka Topics:
  - nova.identity.events
    - identity.user.created { user_id, username, email, created_at }
    - identity.user.profile_updated { user_id, username, display_name, updated_at }
    - identity.user.deleted { user_id, deleted_at, soft_delete }
```

**架构评分:**
- ✅ 职责单一 (仅处理身份认证)
- ✅ 无外部服务依赖
- ✅ 支持 JWT (无状态认证)
- ⚠️ 可能与 social-service 的用户资料功能重叠

**风险点:**
- 🔴 **高危:** 存储敏感数据 (密码哈希)，需严格加密
- 🟡 **中危:** Session 管理需要 Redis 备份 (防止登出失效)

---

### 2. content-service (内容管理核心)

**核心职责:**
- ✅ 创建、编辑、删除帖子 (Post CRUD)
- ✅ 内容审核状态管理 (draft, published, archived)
- ✅ 内容分类与标签 (tags)
- ✅ 多媒体关联 (media_ids)
- ✅ 内容可见性控制 (public, followers, private)

**API 示例:**
```protobuf
service ContentService {
  rpc CreatePost(CreatePostRequest) returns (CreatePostResponse);
  rpc UpdatePost(UpdatePostRequest) returns (UpdatePostResponse);
  rpc DeletePost(DeletePostRequest) returns (DeletePostResponse);
  rpc GetPost(GetPostRequest) returns (Post);
  rpc ListUserPosts(ListUserPostsRequest) returns (ListPostsResponse);
}
```

**数据库 Schema:**
```sql
CREATE TABLE posts (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  content TEXT NOT NULL,
  type VARCHAR(20) CHECK (type IN ('text', 'image', 'video', 'link')),
  visibility VARCHAR(20) DEFAULT 'public',
  media_ids UUID[],
  tags TEXT[],
  status VARCHAR(20) DEFAULT 'published',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_posts_user_id ON posts(user_id);
CREATE INDEX idx_posts_created_at ON posts(created_at DESC);
CREATE INDEX idx_posts_tags ON posts USING GIN(tags);
```

**事件发布:**
```
Kafka Topics:
  - nova.content.events (6 partitions)
    - PostCreated { post_id, user_id, content, type, visibility, tags }
    - PostUpdated { post_id, content, updated_at }
    - PostDeleted { post_id, user_id }
```

**消费事件:**
```
Kafka Topics:
  - nova.media.events
    - MediaUploaded { post_id, media_url } → 自动关联到 post
```

**架构评分:**
- ✅ 核心业务逻辑清晰
- ✅ 事件驱动架构已实现
- ✅ 支持多种内容类型
- ⚠️ 缺少内容版本历史 (revision history)

**风险点:**
- 🟡 **中危:** 软删除 vs 硬删除策略未明确
- 🟡 **中危:** 大量 tags 可能导致查询慢 (需要 GIN 索引)

---

### 3. media-service (媒体上传与处理)

**核心职责:**
- ✅ 文件上传到 S3 (图片、视频、音频)
- ✅ 生成预签名 URL (临时访问)
- ✅ 图片压缩与缩略图生成
- ✅ 视频转码 (可选，可能委托给 AWS MediaConvert)
- ✅ CDN 加速配置

**API 示例:**
```protobuf
service MediaService {
  rpc UploadMedia(stream UploadMediaRequest) returns (UploadMediaResponse);
  rpc GetMediaUrl(GetMediaUrlRequest) returns (MediaUrl);
  rpc DeleteMedia(DeleteMediaRequest) returns (DeleteMediaResponse);
  rpc GeneratePresignedUrl(GeneratePresignedUrlRequest) returns (PresignedUrl);
}
```

**数据库 Schema:**
```sql
CREATE TABLE media (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  post_id UUID,  -- 可能为空，上传时未关联
  type VARCHAR(20) CHECK (type IN ('image', 'video', 'audio')),
  s3_key TEXT NOT NULL,
  s3_bucket VARCHAR(255) NOT NULL,
  url TEXT NOT NULL,
  thumbnail_url TEXT,
  size_bytes BIGINT,
  mime_type VARCHAR(100),
  created_at TIMESTAMPTZ DEFAULT NOW()
);
```

**事件发布:**
```
Kafka Topics:
  - nova.media.events (3 partitions)
    - MediaUploaded { media_id, post_id, url, type }
    - MediaDeleted { media_id }
```

**架构评分:**
- ✅ 职责单一 (仅处理媒体)
- ✅ 解耦良好 (通过 Kafka 与 content-service 通信)
- ✅ S3 集成标准
- ⚠️ 缺少媒体元数据提取 (EXIF, 视频时长)

**风险点:**
- 🟡 **中危:** S3 权限配置错误可能导致媒体泄露
- 🟡 **中危:** 大文件上传需要分片上传 (multipart upload)
- 🟢 **低危:** CDN 缓存失效策略需要明确

---

### 4. messaging-service (私信与消息)

**核心职责:**
- ✅ 1对1 私信 (Direct Message)
- ✅ 群聊消息 (Group Chat)
- ✅ 消息加密 (可选，端到端加密)
- ✅ 消息已读状态
- ✅ 消息历史查询

**API 示例:**
```protobuf
service MessagingService {
  rpc SendMessage(SendMessageRequest) returns (SendMessageResponse);
  rpc GetConversation(GetConversationRequest) returns (Conversation);
  rpc ListConversations(ListConversationsRequest) returns (ListConversationsResponse);
  rpc MarkAsRead(MarkAsReadRequest) returns (MarkAsReadResponse);
}
```

**数据库 Schema:**
```sql
CREATE TABLE conversations (
  id UUID PRIMARY KEY,
  type VARCHAR(20) CHECK (type IN ('direct', 'group')),
  participant_ids UUID[],
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE messages (
  id UUID PRIMARY KEY,
  conversation_id UUID REFERENCES conversations(id),
  sender_id UUID NOT NULL,
  content TEXT NOT NULL,
  is_encrypted BOOLEAN DEFAULT FALSE,
  read_by UUID[],
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_messages_conversation ON messages(conversation_id, created_at DESC);
```

**事件发布:**
```
Kafka Topics:
  - nova.message.events (3 partitions)
    - MessageSent { message_id, conversation_id, sender_id, content }
    - MessageRead { message_id, reader_id, timestamp }
```

**架构评分:**
- ✅ 支持 1对1 和群聊
- ✅ 消息持久化到 Postgres
- ⚠️ 缺少消息撤回功能
- ⚠️ 缺少消息编辑功能

**风险点:**
- 🟡 **中危:** 大量未读消息可能导致查询慢
- 🟡 **中危:** 端到端加密实现复杂度高
- 🟢 **低危:** 消息分页需要优化 (cursor-based pagination)

---

### 5. search-service (全文搜索)

**核心职责:**
- ✅ 内容全文搜索 (Elasticsearch)
- ✅ 用户搜索 (username, bio)
- ✅ 标签搜索 (hashtags)
- ✅ 搜索结果排序 (相关性、时间)
- ✅ 搜索建议 (autocomplete)

**API 示例:**
```protobuf
service SearchService {
  rpc SearchPosts(SearchPostsRequest) returns (SearchPostsResponse);
  rpc SearchUsers(SearchUsersRequest) returns (SearchUsersResponse);
  rpc SearchTags(SearchTagsRequest) returns (SearchTagsResponse);
  rpc AutocompleteSuggestions(AutocompleteRequest) returns (AutocompleteResponse);
}
```

**Elasticsearch Index:**
```json
{
  "posts": {
    "mappings": {
      "properties": {
        "post_id": { "type": "keyword" },
        "user_id": { "type": "keyword" },
        "content": { "type": "text", "analyzer": "standard" },
        "tags": { "type": "keyword" },
        "created_at": { "type": "date" }
      }
    }
  },
  "users": {
    "mappings": {
      "properties": {
        "user_id": { "type": "keyword" },
        "username": { "type": "text", "analyzer": "standard" },
        "bio": { "type": "text" }
      }
    }
  }
}
```

**消费事件:**
```
Kafka Topics:
  - nova.content.events → 索引新帖子到 Elasticsearch
  - nova.identity.events → 索引新用户
```

**架构评分:**
- ✅ 专用搜索服务，职责清晰
- ✅ Elasticsearch 集成
- ⚠️ 缺少搜索分析 (热门搜索词)
- ⚠️ 缺少搜索过滤 (日期范围、作者)

**风险点:**
- 🟡 **中危:** Elasticsearch 与 Postgres 数据同步延迟
- 🟡 **中危:** 搜索索引需要定期重建
- 🟢 **低危:** 搜索结果需要去重

---

### 6. notification-service (通知推送)

**核心职责:**
- ✅ Push 通知 (APNs, FCM)
- ✅ Web 推送 (WebSocket)
- ✅ Email 通知
- ✅ 通知历史记录
- ✅ 通知偏好设置

**API 示例:**
```protobuf
service NotificationService {
  rpc SendNotification(SendNotificationRequest) returns (SendNotificationResponse);
  rpc GetNotifications(GetNotificationsRequest) returns (GetNotificationsResponse);
  rpc MarkAsRead(MarkAsReadRequest) returns (MarkAsReadResponse);
  rpc UpdatePreferences(UpdatePreferencesRequest) returns (UpdatePreferencesResponse);
}
```

**数据库 Schema (Redis):**
```redis
# 用户未读通知计数
notification:unread:{user_id} → integer

# 通知列表 (sorted set by timestamp)
notification:list:{user_id} → {timestamp} {notification_json}

# 通知偏好
notification:preferences:{user_id} → {email: true, push: false}
```

**消费事件:**
```
Kafka Topics:
  - nova.social.events → social.like.created → 通知作者
  - nova.message.events (legacy message_persisted) → message.persisted → 通知接收者
  - nova.social.events → social.follow.created → 通知被关注者
```

**架构评分:**
- ✅ 支持多种通知渠道
- ✅ Redis 实时计数
- ⚠️ 缺少通知去重逻辑 (同一事件多次通知)
- ⚠️ 缺少通知优先级 (重要通知优先推送)

**风险点:**
- 🟡 **中危:** Push token 过期需要自动清理
- 🟢 **低危:** Email 通知需要限流 (防止被标记为垃圾邮件)

---

### 7. graphql-gateway (API 网关) ⏸️ 禁用

**核心职责:**
- ✅ GraphQL API 统一入口
- ✅ 服务编排 (聚合多个 gRPC 服务)
- ✅ 认证中间件 (JWT 验证)
- ✅ 限流与熔断
- ✅ 日志与监控

**GraphQL Schema 示例:**
```graphql
type Query {
  me: User!
  post(id: ID!): Post
  feed(limit: Int, offset: Int): [Post!]!
  searchPosts(query: String!): [Post!]!
  conversation(id: ID!): Conversation
}

type Mutation {
  createPost(input: CreatePostInput!): Post!
  likePost(postId: ID!): Boolean!
  sendMessage(input: SendMessageInput!): Message!
}

type Subscription {
  newMessage(conversationId: ID!): Message!
  newNotification: Notification!
}
```

**架构评分:**
- ✅ 提供统一的 API 接口
- ✅ GraphQL 支持客户端按需查询
- ⚠️ 当前禁用，可能影响客户端开发
- ⚠️ 缺少 GraphQL 查询复杂度限制 (防止滥用)

**风险点:**
- 🔴 **高危:** 禁用后客户端无法访问 API
- 🟡 **中危:** N+1 查询问题需要 DataLoader 解决

**建议:**
- 🔧 **立即启用** - 这是客户端唯一的 API 入口

---

### 8. feed-service (动态信息流) ⏸️ 禁用

**核心职责:**
- ✅ 生成用户个性化 Feed
- ✅ 时间线排序 (时间、热度)
- ✅ Feed 缓存 (Redis)
- ✅ 关注用户的内容聚合

**API 示例:**
```protobuf
service FeedService {
  rpc GetFeed(GetFeedRequest) returns (GetFeedResponse);
  rpc RefreshFeed(RefreshFeedRequest) returns (RefreshFeedResponse);
}
```

**Redis Schema:**
```redis
# 用户 Feed (sorted set by timestamp)
feed:{user_id} → {timestamp} {post_id}

# 热门 Feed (全局)
feed:trending → {score} {post_id}
```

**消费事件:**
```
Kafka Topics:
  - nova.content.events → PostCreated → 推送到粉丝 feed
```

**架构评分:**
- ✅ 专用 Feed 服务，性能优化
- ✅ Redis 缓存加速
- ⚠️ 当前禁用，用户无法看到 Feed
- ⚠️ 缺少算法排序 (仅时间排序)

**风险点:**
- 🔴 **高危:** 禁用后核心功能不可用
- 🟡 **中危:** 粉丝数过多 (> 10万) 时 Feed 更新慢

**建议:**
- 🔧 **高优先级启用** - 这是社交媒体核心功能

---

### 9. social-service (社交关系) ⏸️ 禁用

**核心职责:**
- ✅ 关注/取消关注
- ✅ 点赞/取消点赞
- ✅ 评论 CRUD
- ✅ 分享/转发
- ✅ 社交图谱查询 (共同关注、粉丝列表)

**API 示例:**
```protobuf
service SocialService {
  rpc Follow(FollowRequest) returns (FollowResponse);
  rpc Unfollow(UnfollowRequest) returns (UnfollowResponse);
  rpc LikePost(LikePostRequest) returns (LikePostResponse);
  rpc CommentPost(CommentPostRequest) returns (CommentPostResponse);
  rpc GetFollowers(GetFollowersRequest) returns (GetFollowersResponse);
}
```

**数据库 Schema:**
```sql
CREATE TABLE follows (
  follower_id UUID NOT NULL,
  followee_id UUID NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (follower_id, followee_id)
);

CREATE TABLE likes (
  user_id UUID NOT NULL,
  post_id UUID NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (user_id, post_id)
);

CREATE TABLE comments (
  id UUID PRIMARY KEY,
  post_id UUID NOT NULL,
  user_id UUID NOT NULL,
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
```

**事件发布:**
```
Kafka Topics:
  - nova.social.events
    - UserFollowed { follower_id, followee_id }
    - PostLiked { user_id, post_id }
    - PostCommented { comment_id, post_id, user_id }
```

**架构评分:**
- ✅ 社交核心功能齐全
- ⚠️ 当前禁用，用户无法互动
- ⚠️ 可能与其他服务功能重叠 (评论应该在 content-service?)

**风险点:**
- 🔴 **高危:** 禁用后社交功能完全不可用
- 🟡 **中危:** 大量点赞/评论需要分页优化

**建议:**
- 🔧 **高优先级启用** - 社交媒体核心功能

---

### 10. graph-service (社交图谱) ⏸️ 禁用

**核心职责:**
- ✅ 使用 Neo4j 存储用户关系图
- ✅ 推荐算法 (共同好友、可能认识的人)
- ✅ 社交距离计算 (度数分离)
- ✅ 社区发现 (Louvain 算法)

**API 示例:**
```protobuf
service GraphService {
  rpc GetRecommendedUsers(GetRecommendedUsersRequest) returns (GetRecommendedUsersResponse);
  rpc FindShortestPath(FindShortestPathRequest) returns (FindShortestPathResponse);
  rpc GetMutualFollowers(GetMutualFollowersRequest) returns (GetMutualFollowersResponse);
}
```

**Neo4j Cypher 查询示例:**
```cypher
// 查找共同关注
MATCH (a:User {id: $user_a})-[:FOLLOWS]->(mutual)<-[:FOLLOWS]-(b:User {id: $user_b})
RETURN mutual

// 推荐用户 (2度关系)
MATCH (me:User {id: $my_id})-[:FOLLOWS]->()-[:FOLLOWS]->(recommended)
WHERE NOT (me)-[:FOLLOWS]->(recommended) AND me <> recommended
RETURN recommended, COUNT(*) AS common_follows
ORDER BY common_follows DESC
LIMIT 10
```

**架构评分:**
- ✅ 专用图数据库，查询高效
- ✅ 支持复杂社交推荐
- ⚠️ 当前禁用，推荐功能不可用
- ⚠️ 与 social-service 数据需要同步

**风险点:**
- 🟡 **中危:** Neo4j 数据与 Postgres 同步延迟
- 🟢 **低危:** 图算法计算成本高

**建议:**
- 🔧 **中优先级启用** - 推荐功能对用户留存重要

---

### 11. analytics-service (数据分析) ⏸️ 禁用

**核心职责:**
- ✅ 实时数据采集 (Kafka)
- ✅ 数据聚合到 ClickHouse
- ✅ 用户行为分析 (PV, UV, 留存率)
- ✅ 内容分析 (热门帖子、趋势话题)
- ✅ 漏斗分析 (转化率)

**API 示例:**
```protobuf
service AnalyticsService {
  rpc TrackEvent(TrackEventRequest) returns (TrackEventResponse);
  rpc GetUserStats(GetUserStatsRequest) returns (UserStats);
  rpc GetContentStats(GetContentStatsRequest) returns (ContentStats);
  rpc GetTrendingTopics(GetTrendingTopicsRequest) returns (TrendingTopicsResponse);
}
```

**ClickHouse Schema:**
```sql
CREATE TABLE events (
  event_id UUID,
  user_id UUID,
  event_type String,
  event_data String,
  timestamp DateTime
) ENGINE = MergeTree()
ORDER BY (event_type, timestamp);

CREATE MATERIALIZED VIEW daily_active_users AS
SELECT
  toDate(timestamp) AS date,
  uniqExact(user_id) AS dau
FROM events
GROUP BY date;
```

**消费事件:**
```
Kafka Topics (全部):
  - nova.identity.events
  - nova.content.events
  - nova.social.events
  - nova.message.events
```

**架构评分:**
- ✅ ClickHouse 适合大数据分析
- ✅ 实时数据流处理
- ⚠️ 当前禁用，无法查看数据统计
- ⚠️ 缺少数据可视化界面

**风险点:**
- 🟡 **中危:** ClickHouse 数据量大后查询变慢
- 🟢 **低危:** 需要定期清理历史数据

**建议:**
- 🔧 **低优先级** - 可以用外部工具 (Google Analytics) 替代

---

### 12. ranking-service (内容排序) ⏸️ 禁用

**核心职责:**
- ✅ Feed 排序算法 (热度、相关性)
- ✅ 机器学习模型预测 (用户喜好)
- ✅ A/B 测试框架
- ✅ 排序特征计算 (点赞数、评论数、时间衰减)

**API 示例:**
```protobuf
service RankingService {
  rpc RankPosts(RankPostsRequest) returns (RankPostsResponse);
  rpc PredictEngagement(PredictEngagementRequest) returns (PredictEngagementResponse);
}
```

**Redis Schema:**
```redis
# 内容热度分数
ranking:score:{post_id} → float (热度分数)

# 用户兴趣向量
ranking:user_vector:{user_id} → json (特征向量)
```

**架构评分:**
- ✅ 专用排序服务，算法独立迭代
- ⚠️ 当前禁用，Feed 仅按时间排序
- ⚠️ 可能与 feed-service 功能重叠

**风险点:**
- 🟡 **中危:** 机器学习模型更新需要自动化
- 🟢 **低危:** A/B 测试需要流量分割

**建议:**
- 🔧 **中优先级** - 提升用户参与度

---

### 13. realtime-chat-service (实时聊天) ⏸️ 禁用

**核心职责:**
- ✅ WebSocket 连接管理
- ✅ 实时消息推送
- ✅ 在线状态显示
- ✅ 输入状态提示 ("正在输入...")
- ✅ 消息已读回执

**API 示例:**
```protobuf
service RealtimeChatService {
  rpc ConnectWebSocket(ConnectWebSocketRequest) returns (stream ChatMessage);
  rpc SendTypingIndicator(SendTypingIndicatorRequest) returns (SendTypingIndicatorResponse);
  rpc UpdateOnlineStatus(UpdateOnlineStatusRequest) returns (UpdateOnlineStatusResponse);
}
```

**Redis Schema:**
```redis
# WebSocket 连接映射
ws:connection:{user_id} → {connection_id}

# 在线状态
user:online:{user_id} → {timestamp}

# 输入状态
typing:{conversation_id}:{user_id} → {timestamp}
```

**消费事件:**
```
Kafka Topics:
  - nova.message.events → MessageSent → 实时推送给接收者
```

**架构评分:**
- ✅ WebSocket 实时通信
- ⚠️ 当前禁用，无实时聊天功能
- ⚠️ 需要负载均衡支持 WebSocket

**风险点:**
- 🟡 **中危:** WebSocket 连接数过多需要限制
- 🟡 **中危:** 连接断开需要自动重连

**建议:**
- 🔧 **高优先级启用** - 实时聊天是重要功能

---

### 14. trust-safety-service (内容审核) ⏸️ 禁用

**核心职责:**
- ✅ 内容审核 (敏感词过滤)
- ✅ 垃圾内容检测 (spam detection)
- ✅ 用户举报处理
- ✅ 自动封禁/限流
- ✅ 机器学习分类 (有害内容)

**API 示例:**
```protobuf
service TrustSafetyService {
  rpc ModerateContent(ModerateContentRequest) returns (ModerateContentResponse);
  rpc ReportContent(ReportContentRequest) returns (ReportContentResponse);
  rpc BanUser(BanUserRequest) returns (BanUserResponse);
  rpc GetContentScore(GetContentScoreRequest) returns (ContentScore);
}
```

**数据库 Schema:**
```sql
CREATE TABLE reports (
  id UUID PRIMARY KEY,
  reporter_id UUID NOT NULL,
  content_id UUID NOT NULL,
  content_type VARCHAR(20),
  reason VARCHAR(100),
  status VARCHAR(20) DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE bans (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  reason TEXT,
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
```

**消费事件:**
```
Kafka Topics:
  - nova.content.events → PostCreated → 自动审核
  - nova.message.events → MessageSent → 自动审核
```

**架构评分:**
- ✅ 专用审核服务，算法独立
- ⚠️ 当前禁用，无内容审核
- ⚠️ 缺少人工审核工作流

**风险点:**
- 🔴 **高危:** 禁用后无法过滤有害内容
- 🟡 **中危:** 机器学习模型需要持续训练

**建议:**
- 🔧 **高优先级启用** - 内容安全合规必需

---

### 15. communication-service (疑似重复) ❓

**分析:**
- ❓ 与 messaging-service 功能重叠
- ❓ 可能是历史遗留服务
- ❓ 需要确认是否可以移除

**建议:**
- 🔍 **需要调查** - 确认功能后决定保留或删除

---

## 功能重叠分析

### 1. 用户资料管理重叠

**问题:**
```
identity-service:
  - username, email, avatar (认证相关)

social-service:
  - bio, location, website (社交资料)

❌ 职责不清晰：用户资料应该统一管理
```

**解决方案:**
```
方案 A: identity-service 只管认证，social-service 管理完整资料
方案 B: 合并到 identity-service，重命名为 user-service

推荐: 方案 A (职责分离)
```

---

### 2. Feed 排序重叠

**问题:**
```
feed-service:
  - 生成 Feed
  - 简单时间排序

ranking-service:
  - 计算热度分数
  - 机器学习排序

❌ 功能分散，算法迭代困难
```

**解决方案:**
```
ranking-service 提供排序分数
    ↓
feed-service 使用分数排序

两个服务协作，职责清晰
```

---

### 3. 实时通信重叠

**问题:**
```
messaging-service:
  - 消息持久化
  - 历史查询

realtime-chat-service:
  - WebSocket 推送
  - 实时状态

✅ 职责分离合理，保持现状
```

---

## 缺失功能识别

### 1. 缺少：用户资料服务 (User Profile Service)

**当前状态:**
- identity-service: 仅认证信息
- social-service: 禁用

**缺失功能:**
- 完整用户资料 (bio, location, website)
- 用户设置 (隐私、通知偏好)
- 用户统计 (粉丝数、帖子数)

**建议:**
```
创建 user-profile-service 或启用 social-service
```

---

### 2. 缺少：评论服务 (Comment Service)

**当前状态:**
- social-service 包含评论功能，但禁用

**缺失功能:**
- 多级评论 (回复评论)
- 评论排序 (热度、时间)
- 评论审核

**建议:**
```
方案 A: 启用 social-service
方案 B: 将评论功能移到 content-service (推荐)
```

---

### 3. 缺少：推荐服务 (Recommendation Service)

**当前状态:**
- graph-service 包含推荐，但禁用
- ranking-service 包含推荐，但禁用

**缺失功能:**
- 内容推荐 (For You 页面)
- 用户推荐 (可能认识的人)
- 话题推荐

**建议:**
```
启用 graph-service + ranking-service
```

---

### 4. 缺少：支付服务 (Payment Service)

**当前状态:**
- 完全缺失

**可能需要:**
- 会员订阅
- 虚拟礼物
- 付费内容

**建议:**
```
暂不需要，未来可扩展
```

---

### 5. 缺少：直播服务 (Live Streaming Service)

**当前状态:**
- turn-server 存在但禁用

**可能需要:**
- WebRTC 直播
- 实时互动

**建议:**
```
Phase 2 功能，暂不启用
```

---

## 架构建议

### 立即启用的关键服务 (P0)

```
1. graphql-gateway     - 客户端 API 入口，必须启用
2. feed-service        - 核心 Feed 功能
3. social-service      - 点赞、评论、关注
4. realtime-chat       - 实时聊天
5. trust-safety        - 内容安全合规
```

**预计资源需求:**
- CPU: +500m (每个服务 100m)
- Memory: +2.5Gi (每个服务 512Mi)

---

### 中期启用的增强服务 (P1)

```
1. graph-service       - 用户推荐
2. ranking-service     - Feed 智能排序
3. analytics-service   - 数据分析
```

---

### 长期功能扩展 (P2)

```
1. turn-server         - 视频通话
2. payment-service     - 支付功能 (新建)
3. live-streaming      - 直播功能 (新建)
```

---

### 需要清理的服务

```
1. communication-service  - 与 messaging-service 重复，建议删除
```

---

## 服务依赖关系总结

```
客户端
  ↓
graphql-gateway (API Gateway)
  ↓
┌─────────────────────────────────────────┐
│ 核心服务层 (Layer 1)                     │
│                                         │
│ identity-service    content-service     │
│ media-service       messaging-service   │
│ search-service      notification        │
└─────────────────────────────────────────┘
  ↓
┌─────────────────────────────────────────┐
│ 增强服务层 (Layer 2)                     │
│                                         │
│ feed-service        social-service      │
│ realtime-chat       trust-safety        │
│ graph-service       ranking-service     │
│ analytics-service                       │
└─────────────────────────────────────────┘
  ↓
┌─────────────────────────────────────────┐
│ 基础设施层 (Layer 0)                     │
│                                         │
│ Postgres  Redis  Kafka  Elasticsearch   │
│ ClickHouse  Neo4j  S3                   │
└─────────────────────────────────────────┘
```

---

## 最终评分

| 评估维度 | 评分 | 说明 |
|---------|------|------|
| 服务职责清晰度 | ⭐⭐⭐⭐ | 大部分服务职责明确，有少量重叠 |
| 功能完整性 | ⭐⭐⭐ | 核心功能齐全，但多数服务禁用 |
| 架构解耦度 | ⭐⭐⭐⭐⭐ | 事件驱动架构，完全解耦 |
| 可扩展性 | ⭐⭐⭐⭐⭐ | 微服务架构，易于扩展 |
| 运维复杂度 | ⭐⭐⭐ | 服务较多，需要编排工具 |

**总分: 20/25 ⭐**

---

## 核心建议

### ✅ 立即行动

1. **启用 graphql-gateway** - 否则客户端无法访问 API
2. **启用 feed-service** - 核心 Feed 功能
3. **启用 social-service** - 点赞、评论、关注
4. **启用 trust-safety-service** - 内容安全合规必需

### ⚠️ 需要调查

1. **communication-service** - 确认是否与 messaging-service 重复
2. **用户资料管理** - 明确 identity vs social 职责分工

### 🔧 长期优化

1. **合并重叠功能** - ranking 与 feed 协作
2. **补充缺失功能** - 评论、推荐
3. **启用监控** - Prometheus + Grafana

---

**结论:**

你的微服务架构设计合理，职责分工清晰，事件驱动解耦良好。主要问题是 **大量核心服务被禁用**，导致功能不完整。建议按优先级逐步启用服务，同时清理重复服务 (communication-service)。
