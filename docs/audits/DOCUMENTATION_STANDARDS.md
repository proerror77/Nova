# Nova 后端文档标准

**版本**：1.0
**最后更新**：2025年11月22日
**适用范围**：所有后端服务、库和工具

---

## 目录

1. [文档结构规范](#文档结构规范)
2. [服务级文档模板](#服务级文档模板)
3. [代码文档规范](#代码文档规范)
4. [API文档规范](#api文档规范)
5. [Proto文档规范](#proto文档规范)
6. [配置文档规范](#配置文档规范)
7. [维护指南](#维护指南)

---

## 文档结构规范

### 所有服务必须有

```
backend/{service}/
├── README.md                      # ⭐ 必须 - 服务总览
├── src/
│   └── main.rs                   # ⭐ 必须有顶级文档注释
├── Cargo.toml                     # 可选：添加description字段
└── migrations/                    # 如果有数据库变更
    └── *.sql                      # 每个迁移前加注释
```

### 可选但推荐

```
backend/{service}/
├── API_DOCUMENTATION.md           # 如果有REST API
├── DEPLOYMENT.md                  # 如果有特殊部署需求
├── TROUBLESHOOTING.md            # 常见问题和解决方案
└── ARCHITECTURE.md               # 如果服务内部复杂
```

### 禁止

```
backend/{service}/
├── ❌ TEMP_*.md                  # 临时文件不提交
├── ❌ OLD_*.md                   # 旧文档使用[DEPRECATED]标记
└── ❌ TODO_*.md                  # TODO应该在代码或issues中
```

---

## 服务级文档模板

### README.md 标准结构

每个服务的 README.md 应该遵循这个结构。使用此作为模板：

```markdown
# {Service Name}

## 📋 概述

[一句话说明这个服务做什么]

[2-3句话详细说明职责范围]

## 🎯 核心职责

- 职责1：详细说明
- 职责2：详细说明
- 职责3：详细说明

## 🏗️ 架构

### 依赖关系

这个服务依赖：
```
- PostgreSQL (posts, comments)
- Redis (caching)
- Kafka (events)
- {other-service} (gRPC calls)
```

### 数据流

[简单的ASCII图表或描述]

```
User Request
    ↓
REST/gRPC Handler
    ↓
Business Logic
    ↓
Database/Cache
```

## 🚀 快速开始

### 前置条件

- Rust 1.70+
- Docker
- PostgreSQL 15+
- Redis 7+

### 本地开发

```bash
# 1. 设置环境
export DATABASE_URL=postgresql://user:pass@localhost/nova
export REDIS_URL=redis://localhost:6379

# 2. 运行迁移
cargo run --bin content-service-migrate

# 3. 启动服务
cargo run --bin content-service
```

### 验证启动

```bash
# 健康检查
curl http://localhost:{PORT}/health

# 如果有gRPC
grpcurl -plaintext localhost:{GRPC_PORT} list
```

## 📡 API 文档

### REST API

[如果有REST API，列出主要端点]

```bash
GET    /api/v1/posts              # 获取帖子列表
POST   /api/v1/posts              # 创建新帖子
GET    /api/v1/posts/{id}         # 获取单个帖子
PUT    /api/v1/posts/{id}         # 更新帖子
DELETE /api/v1/posts/{id}         # 删除帖子
```

详见 [API_DOCUMENTATION.md](API_DOCUMENTATION.md)

### gRPC 服务

[如果有gRPC，列出主要服务]

```protobuf
service ContentService {
  rpc GetPost(GetPostRequest) returns (GetPostResponse);
  rpc ListPosts(ListPostsRequest) returns (ListPostsResponse);
  rpc CreatePost(CreatePostRequest) returns (CreatePostResponse);
}
```

详见 Proto 文件：`proto/services_v2/content_service.proto`

## ⚙️ 配置

### 环境变量

| 变量 | 必须 | 默认值 | 说明 |
|------|------|--------|------|
| `DATABASE_URL` | ✅ | 无 | PostgreSQL连接字符串 |
| `REDIS_URL` | ✅ | 无 | Redis连接地址 |
| `KAFKA_BROKERS` | ✅ | 无 | Kafka broker列表 |
| `LOG_LEVEL` | ❌ | info | 日志级别：trace/debug/info/warn/error |

详见 `../../.env.example`

### 启动参数

```bash
# 自定义端口
PORT=8081 cargo run

# 自定义日志级别
RUST_LOG=debug cargo run

# 启用分析
ENABLE_PROFILING=true cargo run
```

## 🗄️ 数据库

### Schema

主要表：
- `posts` - 用户发布的内容
- `comments` - 评论
- `posts_media` - 媒体附件

关键索引：
- `idx_posts_author_id` - 加速按作者查询
- `idx_posts_created_at` - 加速时间范围查询

### 迁移

```bash
# 运行所有待处理迁移
sqlx migrate run

# 回滚最后一个迁移
sqlx migrate revert
```

## 🔄 与其他服务的集成

### 依赖的服务

**feed-service** (gRPC)
- 调用 `GetFeedRequest` 获取推荐内容
- 使用 `{service_name}` port `{port}`

**social-service** (gRPC)
- 获取点赞数、评论数
- 使用 `{service_name}` port `{port}`

### 依赖这个服务的服务

**graphql-gateway** (REST)
- 调用所有 REST 端点
- 使用 `content-service` port `8081`

**notification-service** (gRPC)
- 接收 `PostCreated` 事件
- Kafka topic: `nova.content.events`

## 📊 监控

### 关键指标

```
# 延迟
content_service_request_duration_ms

# 吞吐量
content_service_requests_total

# 错误
content_service_errors_total
```

### 健康检查

```bash
# 完整的健康检查（包含数据库、缓存、依赖）
curl http://localhost:8081/health/deep
```

### 常见告警

- `HighLatency` - 请求延迟 > 1000ms
- `HighErrorRate` - 错误率 > 5%
- `CacheHitRate` - 缓存命中率 < 70%

## 🐛 故障排查

### 问题：启动失败

**错误**：`connection refused`
**原因**：PostgreSQL 未运行
**解决**：`docker-compose up postgres`

### 问题：缓存未命中

**检查**：Redis 是否可达
```bash
redis-cli ping
```

### 更多帮助

详见 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

## 📈 性能

### 关键参数

```
DATABASE_POOL_SIZE=20           # 数据库连接池大小
REDIS_POOL_SIZE=50              # Redis连接池大小
CACHE_TTL_SECS=3600            # 缓存过期时间
REQUEST_TIMEOUT_SECS=30        # 请求超时时间
```

详见 [PERFORMANCE_TUNING.md](PERFORMANCE_TUNING.md)

## 🔐 安全

- 所有 API 端点都需要 JWT 认证
- 不在日志中输出 PII（个人识别信息）
- 使用参数化查询防止 SQL 注入

详见 `../../docs/SECURITY_GUIDE.md`

## 🤝 贡献

在修改此服务时：

- [ ] 修改了API？更新本文档
- [ ] 修改了数据库schema？运行迁移并记录
- [ ] 改变了依赖关系？更新"集成"部分
- [ ] 修改了配置？更新"环境变量"表

## 📚 相关文档

- [系统架构](../ARCHITECTURE.md)
- [服务清单](../SERVICES_OVERVIEW.md)
- [部署指南](../DEPLOYMENT_GUIDE.md)
- [API参考](../API_REFERENCE.md)

## 📞 支持

- **Slack**：#nova-backend
- **Issues**：GitHub Issues 标签 `content-service`
- **维护者**：[@team-backend](https://github.com/orgs/nova/teams/backend)
```

### 文件大小指南

- **最小**：50行（很小的服务）
- **目标**：100-150行（大多数服务）
- **最大**：200行（复杂服务，应该考虑分割）

> 如果 README 超过200行，考虑创建子文档（ARCHITECTURE.md, API_DOCUMENTATION.md等）

---

## 代码文档规范

### 模块级文档

**所有 main.rs 必须有**：

```rust
//! {Service Name} - {One-line description}
//!
//! This service handles {core responsibility}.
//!
//! ## Architecture
//!
//! The service consists of:
//! - REST API (port 8081) for direct client calls
//! - gRPC API (port 9081) for service-to-service communication
//! - PostgreSQL backend for persistent storage
//! - Redis for caching and session management
//!
//! ## Key Components
//!
//! - [`handlers`](crate::handlers) - HTTP request handlers
//! - [`services`](crate::services) - Business logic
//! - [`db`](crate::db) - Database access layer
//! - [`cache`](crate::cache) - Caching layer
//!
//! ## Dependencies
//!
//! This service depends on:
//! - `social-service` for likes and comments
//! - `graph-service` for following relationships
//! - `notification-service` for user notifications
//!
//! ## Configuration
//!
//! See [`.env.example`](../../.env.example) for all available environment variables.
```

### 函数文档

**公开函数（pub fn）必须有**：

```rust
/// Brief description of what this function does
///
/// More detailed explanation of the behavior, parameters, and return value.
/// Include edge cases and important notes.
///
/// # Arguments
///
/// * `param1` - Description of param1
/// * `param2` - Description of param2 and valid range
///
/// # Returns
///
/// A [`Result<T>`](std::result::Result) containing:
/// - [`Ok(T)`](std::result::Ok) with the result data
/// - [`Err(E)`](std::result::Err) if validation fails or database error occurs
///
/// # Errors
///
/// Returns [`ServiceError::NotFound`] if user doesn't exist.
/// Returns [`ServiceError::InvalidInput`] if email format is invalid.
///
/// # Examples
///
/// ```ignore
/// let user = create_user("alice", "alice@example.com").await?;
/// assert_eq!(user.email, "alice@example.com");
/// ```
pub async fn create_user(name: &str, email: &str) -> Result<User> {
    // implementation
}
```

### 结构体和枚举

```rust
/// User account in the system
///
/// Each user has a unique ID and email address. Users can be active or deactivated.
#[derive(Debug, Clone)]
pub struct User {
    /// Unique identifier (UUID)
    pub id: String,

    /// User's email address (normalized to lowercase)
    pub email: String,

    /// Display name (1-255 characters)
    pub name: String,

    /// Account creation timestamp (Unix seconds)
    pub created_at: i64,
}

/// Possible errors from user operations
#[derive(Debug)]
pub enum UserError {
    /// User with given ID not found in database
    NotFound(String),

    /// Email is already registered
    DuplicateEmail(String),

    /// Email format is invalid
    InvalidEmail(String),
}
```

### 复杂业务逻辑

为复杂的方法添加清晰的步骤注释：

```rust
pub fn rank_posts(&self, mut posts: Vec<Post>) -> Vec<RankedPost> {
    // Step 1: Calculate base relevance score for each post
    // This combines recency (newer = higher) and engagement (likes/comments)
    let mut scored_posts: Vec<_> = posts
        .into_iter()
        .map(|post| {
            let recency_score = self.compute_recency(&post);
            let engagement_score = self.compute_engagement(&post);
            let base_score = 0.7 * recency_score + 0.3 * engagement_score;
            (post, base_score)
        })
        .collect();

    // Step 2: Apply personalization based on user interests
    // Boost posts from followed users and related topics
    for (post, score) in &mut scored_posts {
        if self.is_from_followed(&post.author_id) {
            *score *= 1.5;
        }
        if self.matches_interests(&post.content) {
            *score *= 1.2;
        }
    }

    // Step 3: Apply diversity filter (MMR algorithm)
    // Avoid showing too many posts from same author or topic
    scored_posts.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(Ordering::Equal));

    self.apply_diversity_filter(scored_posts)
}
```

---

## API文档规范

### REST API 文档模板

```markdown
# {Service} REST API

## Overview

Brief description of the API's purpose and versioning.

## Authentication

All endpoints require a valid JWT token in the Authorization header:
```
Authorization: Bearer <jwt_token>
```

## Base URL

```
https://api.example.com/api/v1
```

## Endpoints

### Create Post

Creates a new post for the authenticated user.

```http
POST /posts
Content-Type: application/json

{
  "content": "Hello world!",
  "visibility": "public",
  "media_ids": ["uuid1", "uuid2"]
}
```

**Response: 201 Created**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "author_id": "user-123",
  "content": "Hello world!",
  "visibility": "public",
  "created_at": 1700644800,
  "updated_at": 1700644800,
  "like_count": 0,
  "comment_count": 0
}
```

**Error: 400 Bad Request**
```json
{
  "error": "content_empty",
  "message": "Post content cannot be empty"
}
```

### Parameters

| Name | Type | Required | Description |
|------|------|----------|-------------|
| content | string | ✅ | Post content (1-5000 chars) |
| visibility | string | ❌ | public/followers/private (default: public) |
| media_ids | array | ❌ | IDs of attached media |

### Rate Limiting

- Requests: 100 per minute per user
- Response header: `X-RateLimit-Remaining: 99`

### Errors

| Code | Description |
|------|-------------|
| 400 | Invalid input (missing/wrong field) |
| 401 | Missing or invalid JWT token |
| 403 | User doesn't have permission |
| 404 | Post not found |
| 500 | Server error |
```

---

## Proto文档规范

### 文件级文档

```protobuf
syntax = "proto3";

/// # Social Service - Relationships & Engagement
///
/// This service manages all social interactions including:
/// - Following/blocking relationships
/// - Likes, comments, and shares
/// - Feed generation
///
/// All RPC methods require authentication via JWT token.
package nova.social_service.v2;

import "google/protobuf/timestamp.proto";
import "google/protobuf/empty.proto";
```

### Service级文档

```protobuf
/// SocialService provides relationship and engagement operations
///
/// The service ensures:
/// - Consistency: following relationships are atomic
/// - Idempotency: duplicate requests return same result
/// - Performance: operations complete within 100ms
service SocialService {
  // ...methods...
}
```

### RPC方法文档

```protobuf
/// FollowUser establishes a follow relationship between two users.
///
/// This method is idempotent - calling it multiple times with the same
/// parameters returns success. The follower will see posts from the followee
/// in their personalized feed.
///
/// After this call succeeds, the follower should:
/// 1. Update their local following list
/// 2. Refresh their feed to include followee's posts
/// 3. Notify the followee of the new follower
///
/// Error cases:
/// - User cannot follow themselves (returns INVALID_ARGUMENT)
/// - Blocked users cannot follow (returns PERMISSION_DENIED)
/// - Target user doesn't exist (returns NOT_FOUND)
rpc FollowUser(FollowUserRequest) returns (google.protobuf.Empty);
```

### Message类型文档

```protobuf
/// FollowUserRequest initiates a follow relationship
message FollowUserRequest {
  /// UUID of the user who wants to follow (the follower)
  /// Must not be same as followee_id
  /// Must be a valid user ID that exists in the system
  string follower_id = 1;

  /// UUID of the user to be followed (the followee)
  /// Must be a valid user ID that exists in the system
  /// Can point to a private account (follow request pending)
  string followee_id = 2;
}

/// User represents a social media user
message User {
  /// Unique identifier (UUID v4)
  string id = 1;

  /// User's display name (1-100 characters)
  /// Can contain spaces but not newlines
  string display_name = 2;

  /// Number of followers (read-only, updated asynchronously)
  /// May lag by up to 30 seconds in real-time queries
  int32 follower_count = 3;

  /// Account creation time (UTC Unix timestamp)
  /// Immutable after creation
  int64 created_at = 4;
}
```

---

## 配置文档规范

### .env.example 注释标准

```bash
# ==============================================
# {Service Name}
# ==============================================

# PostgreSQL database URL for {service description}
# Format: postgresql://[user[:password]@][netloc][:port][/dbname]
# Example: postgresql://postgres:password@localhost:5432/nova_content
# Required for: content-service, social-service, identity-service
DATABASE_URL=postgresql://postgres:postgres@postgres:5432/nova

# Maximum database connections in the pool
# Recommended: CPU cores * 4 (adjust based on memory)
# Too low: Connection timeouts, poor throughput
# Too high: Memory exhaustion
DATABASE_MAX_CONNECTIONS=10

# Redis cache server URL
# Format: redis://[password@]host[:port][/db]
# When Redis is down: requests slow down but still work (with DB fallback)
# Critical for: feed-service, identity-service
REDIS_URL=redis://redis:6379

# Kafka brokers for event streaming
# Format: comma-separated list of host:port
# Used by: all services for publishing events
# If Kafka is down: events are buffered in outbox table
KAFKA_BROKERS=kafka:9092
```

---

## 维护指南

### 文档审查清单

**代码审查时检查**：

- [ ] 新的公开函数（pub fn）有 /// 文档吗？
- [ ] 修改了 API 端点？更新了 API_DOCUMENTATION.md 吗？
- [ ] 修改了 Proto 文件？添加了 /// 注释吗？
- [ ] 改变了环境变量？更新了 .env.example 吗？
- [ ] 改变了服务职责或架构？更新了 README.md 吗？
- [ ] 添加了新的依赖服务？更新了"集成"部分吗？

### 文档过期检查

**每个月第一个工作日**：

1. 审查 README.md 中的信息
   - [ ] 端口号仍然准确吗？
   - [ ] 配置参数仍然有效吗？
   - [ ] 健康检查端点仍然存在吗？

2. 验证 API 文档
   - [ ] 所有列出的端点仍然存在吗？
   - [ ] 请求/响应格式仍然准确吗？
   - [ ] 所有错误代码仍然有效吗？

3. 检查 Proto 文档
   - [ ] RPC 方法仍然准确吗？
   - [ ] 消息类型没有变化吗？
   - [ ] 版本号（v1/v2）正确吗？

### 标记过时文档

如果发现过时文档但不能立即修复：

```markdown
# ⚠️ [OUTDATED] Service Name

**Last Updated**: 2025-11-22
**Status**: DEPRECATED - Use [new location] instead

This documentation is outdated. For current information, see:
- [New README](../new-service/README.md)
- [Current API Docs](../API_REFERENCE.md)
```

### 版本控制

**所有服务文档应该有**：

```markdown
---
**Document Version**: 1.2.3
**Last Updated**: 2025-11-22
**Compatible With**: Service v1.2.3+
---
```

---

## 工具和格式

### Markdown 格式

- **Headings**: # 作为顶级，逐级递增
- **Code blocks**: 使用语言标记（bash, rust, protobuf）
- **Tables**: 用于结构化数据
- **Lists**: 无序用 `-`，有序用 `1.`
- **Links**: 相对路径用于内部文档

### 推荐的编辑器

- VS Code (Markdown All in One 扩展)
- GitHub Web Editor (简单编辑)
- 任何纯文本编辑器

### 验证文档

```bash
# 检查markdown语法
markdownlint backend/**/*.md

# 检查链接有效性
markdown-link-check backend/**/*.md

# 生成目录
doctoc backend/DOCUMENTATION_STANDARDS.md
```

---

## 常见问题

### Q: 我的服务太小了，需要这么详细的文档吗？

**A**: 至少需要 README.md 和代码级文档。从最小的模板开始，有需要时扩展。

### Q: 文档和代码不一致怎么办？

**A**: 代码是真实的来源。文档不准确时，立即修复。建立 CI 检查来检测不一致。

### Q: 如何保持文档同步？

**A**: 在 PR 中同时提交代码和文档。代码审查时检查文档一致性。

### Q: 历史文档怎么处理？

**A**: 标记为 [OUTDATED]，但不删除（有参考价值）。为新版本创建新文档。

---

## 示例

### 完整的服务文档示例

详见：
- `ranking-service/README.md` - 有架构图的范例
- `search-service/README.md` - 有复杂查询的范例
- `notification-service/API_DOCUMENTATION.md` - REST API 范例

---

**下一步**：应用这些标准到所有服务。参考 DOCUMENTATION_ASSESSMENT.md 中的修复计划。
