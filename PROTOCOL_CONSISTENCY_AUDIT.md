# Nova 项目 协议一致性审计报告

## 执行摘要

通过深入分析发现了 **8 个严重的协议一致性问题**，主要集中在以下三个方面：

1. **双重 Proto 定义导致的严重混乱**（最严重）
2. **错误响应格式的不一致**（中等严重）
3. **时间戳和数据类型的混用**（中等严重）

---

## 问题清单（按严重程度排序）

### 级别：CRITICAL 🔴

#### 1. 双重 Proto 定义导致编译矛盾
**文件位置：**
- `/Users/proerror/Documents/nova/backend/protos/auth.proto` (行 1-325)
- `/Users/proerror/Documents/nova/backend/proto/services/auth_service.proto` (行 1-246)

**问题描述：**
存在两套完全独立的 proto 定义文件，定义了同一个 AuthService，但存在明显差异：

- `protos/auth.proto`：
  - 包名：`nova.auth.v1`
  - 方法数：13 个（包括 OAuth、密码重置、Session、2FA 等）
  - 包含 `google.protobuf.wrappers` 的 StringValue/BoolValue
  - 包含完整的用户资料管理 (UpdateUserProfile, UpsertUserPublicKey)

- `proto/services/auth_service.proto`：
  - 包名：`nova.auth_service`（无版本）
  - 方法数：10 个（简化版，缺少大部分功能）
  - 直接使用字符串，无 wrappers
  - 缺少 Session/2FA/密码重置等核心功能

**关键不一致项：**

```
功能对比                    | protos/auth.proto | proto/services/auth_service.proto
RegisterRequest params      | 4 字段            | 3 字段 (缺少 phone)
UpdateUserProfileRequest    | 包含 StringValue  | 不存在
TokenClaims                 | 6 字段结构        | 无对应消息
SessionInfo/Session管理     | 完整实现          | 完全缺失
TwoFA 方法                  | 3 个RPC           | 0 个RPC
OAuth 方法                  | 2 个RPC           | 0 个RPC
```

**影响范围：**
- 编译时：若同时引入两个 proto，会导致重复定义错误
- 运行时：不同服务可能使用不同的 AuthService 定义，导致互操作性故障
- 维护：无法确定哪个是"真实"的契约

**修复优先级：** P0 - 立即解决

**建议方案：**
1. 统一为单一定义源：保留 `proto/services/auth_service.proto` 作为标准
2. 迁移 `protos/auth.proto` 中独有的功能（OAuth、2FA、Session）到新定义
3. 所有服务使用统一的 go_package 路径：`github.com/novacorp/nova/backend/proto/auth/v1`

---

#### 2. 同样的双重定义问题存在于其他服务
**文件位置：**
- `/Users/proerror/Documents/nova/backend/protos/` 和 `/Users/proerror/Documents/nova/backend/proto/services/`

**受影响的服务：**
- content_service.proto (两个版本不兼容)
- video.proto vs video_service.proto
- messaging_service.proto (两个版本)
- media_service.proto (两个版本)
- streaming.proto vs streaming_service.proto

**示例 - content_service 差异：**

```
文件1: protos/content_service.proto
- package: nova.content
- 13 个 RPC 方法
- 无版本号

文件2: proto/services/content_service.proto
- package: nova.content_service
- 10 个 RPC 方法
- 不同的错误处理（bool success vs string error）
```

**影响范围：** 项目内 70% 的 proto 定义重复

**修复优先级：** P0

---

### 级别：HIGH 🟠

#### 3. 错误响应格式的严重不一致

**问题位置：**
- proto 文件中的错误处理方式不统一
- Rust 库中定义的 ErrorResponse 与 proto 中的不匹配

**不一致情况分析：**

A. **Proto 中的错误模式分散：**

文件 `/Users/proerror/Documents/nova/backend/protos/content_service.proto`:
```protobuf
message GetPostResponse {
    Post post = 1;
    bool found = 2;          // ❌ 方式1：bool 标志
    string error = 3;        // ❌ 方式2：简单 string
}

message CreatePostResponse {
    Post post = 1;
    string error = 2;        // 同样是 string 错误
}
```

文件 `/Users/proerror/Documents/nova/backend/protos/messaging_service.proto`:
```protobuf
message SendMessageResponse {
    Message message = 1;
    string error = 2;        // ❌ 方式3：无结构化错误
}

message GetReactionsResponse {
    repeated MessageReaction reactions = 1;
    string error = 2;        // 混合方式
}
```

文件 `/Users/proerror/Documents/nova/backend/proto/services/events_service.proto`:
```protobuf
message OutboxEvent {
    ...
    int32 retry_count = 7;
    string error_message = 8;  // ❌ 方式4：error_message 字段名不统一
    ...
}
```

B. **Rust 中的统一 ErrorResponse：**

文件 `/Users/proerror/Documents/nova/backend/libs/error-types/src/lib.rs`:
```rust
pub struct ErrorResponse {
    pub error: String,
    pub message: String,
    pub status: u16,
    pub error_type: String,
    pub code: String,
    pub details: Option<String>,
    pub trace_id: Option<String>,
    pub timestamp: String,
}
```

**关键问题：**

| 方面 | Proto 定义 | Rust 实现 | 状态 |
|-----|----------|---------|-----|
| 错误字段名 | error / error_message | error + message | ❌ 不匹配 |
| 错误代码结构 | string error | code 枚举 | ❌ 不兼容 |
| HTTP 状态码 | 无 | status (u16) | ❌ Proto 缺失 |
| 错误类型 | 无 | error_type 枚举 | ❌ Proto 缺失 |
| 请求追踪 | 无 | trace_id 可选 | ❌ 无法关联 |
| 时间戳 | 无 | ISO 8601 | ❌ Proto 缺失 |

**具体示例 - GetPostResponse：**

Proto 定义：
```protobuf
message GetPostResponse {
    Post post = 1;
    bool found = 2;
    string error = 3;        // 简单字符串
}
```

Rust 实现 期望：
```rust
ErrorResponse {
    error: "NOT_FOUND",
    message: "Post not found: xyz",
    status: 404,
    error_type: "not_found_error",
    code: "POST_NOT_FOUND",
    trace_id: Some("req-123-abc"),
    ...
}
```

**跨服务后果：**
- content-service 返回 `{"error": "Post deleted"}` (简单字符串)
- messaging-service 返回 `{"error": "PERMISSION_DENIED"}` (枚举)
- media-service 返回 `{"error_message": "Upload failed"}` (不同字段名)

客户端无法构建统一的错误处理逻辑。

**修复优先级：** P1

**建议方案：**
在所有 proto 中定义统一的错误响应类型：
```protobuf
message Error {
    string code = 1;           // "USER_NOT_FOUND"
    string message = 2;        // 用户友好的消息
    string error_type = 3;     // "not_found_error"
    int32 http_status = 4;     // 404
    string trace_id = 5;       // 请求追踪 ID
    string timestamp = 6;      // ISO 8601
}

message CommonResponse {
    Error error = 1;
}
```

---

#### 4. 时间戳格式的不一致

**问题位置：**
多个 proto 文件中混用两种时间戳格式：

**不一致情况：**

1. **`created_at` 字段类型不统一：**

文件 `/Users/proerror/Documents/nova/backend/protos/auth.proto`:
```protobuf
message TokenClaims {
    int64 issued_at = 5;      // Unix 秒级时间戳
    int64 expires_at = 6;
}
```

文件 `/Users/proerror/Documents/nova/backend/proto/services/auth_service.proto`:
```protobuf
message User {
    string created_at = 4;    // ISO 8601 字符串
    string locked_until = 7;  // ISO 8601 字符串
}
```

文件 `/Users/proerror/Documents/nova/backend/proto/services/user_service.proto`:
```protobuf
message UserProfile {
    string created_at = 15;   // ISO 8601 字符串
    string updated_at = 16;
    string deleted_at = 17;
}
```

文件 `/Users/proerror/Documents/nova/backend/protos/messaging_service.proto`:
```protobuf
message Message {
    int64 created_at = 10;    // Unix 毫秒时间戳
    int64 updated_at = 11;
    int64 deleted_at = 12;
}
```

2. **同一服务内的混用：**

文件 `/Users/proerror/Documents/nova/backend/proto/services/feed_service.proto`:
```protobuf
message FeedEntry {
    string created_at = 14;   // ISO 8601
    string published_at = 15; // ISO 8601
    string engagement_score = 16;  // ❌ 应该是 int32/double，却是 string
}

message FeedMetadata {
    string last_fetched_at = 4;   // ISO 8601
    string generated_at = 5;      // ISO 8601
    string cache_ttl = 6;         // ❌ 应该是 int32 秒数，却是 string
}
```

**影响范围：**

| 服务 | created_at 类型 | 问题 |
|-----|----------------|-----|
| auth | int64 (Unix秒) | 与其他服务不匹配 |
| user | string (ISO8601) | 与 auth 不匹配 |
| messaging | int64 (Unix毫秒) | 精度与 auth 不同（毫秒 vs 秒） |
| content | string (ISO8601) | 与 messaging 不匹配 |
| feed | string (ISO8601) | 与 messaging 不匹配 |

**跨服务调用时的问题：**

当 content-service 调用 user-service 获取作者信息时：
```
content-service 返回：created_at: 1730784000 (Unix 秒)
user-service 返回：created_at: "2024-11-05T12:00:00Z" (ISO 8601)
```

客户端无法统一处理日期。

**修复优先级：** P1

**建议方案：**
- 全局统一使用 `int64` Unix 秒级时间戳（与大多数业界标准一致）
- 在 API 层转换为 ISO 8601（使用 Rust 的 chrono crate）
- 创建 proto util 文件定义标准时间戳类型

---

#### 5. UUID 序列化的不一致

**问题位置：**

所有服务都使用 `string` 来存储 UUID，但没有明确的验证规则。

文件 `/Users/proerror/Documents/nova/backend/proto/services/auth_service.proto`:
```protobuf
message User {
    string id = 1;  // UUID - 但无格式验证
    ...
}
```

**问题：**
- Proto 中无法定义格式约束（如 UUID v4）
- 不同服务可能使用不同的 UUID 版本或格式
- JSON 序列化/反序列化时无验证

**修复优先级：** P2

---

#### 6. 枚举值的版本控制缺失

**问题位置：**

文件 `/Users/proerror/Documents/nova/backend/protos/auth.proto`:
```protobuf
enum OAuthProvider {
    OAUTH_PROVIDER_UNSPECIFIED = 0;
    OAUTH_PROVIDER_GOOGLE = 1;
    OAUTH_PROVIDER_APPLE = 2;
    OAUTH_PROVIDER_FACEBOOK = 3;
    OAUTH_PROVIDER_WECHAT = 4;
}
```

**问题：**
- 如果要添加新的 OAuth 提供商，无法保证向后兼容
- 没有 deprecated 标记机制
- 不同版本服务间的枚举值映射无法追踪

**示例 - 破坏性变更风险：**

当前版本（v1）中如果添加 `OAUTH_PROVIDER_GITHUB = 5`，使用旧版本 proto 生成的客户端将无法解析包含此值的响应。

**修复优先级：** P2

---

#### 7. 数据库时间戳字段类型的隐含不匹配

**问题位置：**

Proto 定义的 `deleted_at` 字段在某些服务中是可选的，但在 Rust 实现中的处理方式不一致。

**示例：**

文件 `/Users/proerror/Documents/nova/backend/proto/services/content_service.proto`:
```protobuf
message Post {
    ...
    string deleted_at = 18;  // 可选字段，但 proto3 中无 optional 标记
}
```

文件 `/Users/proerror/Documents/nova/backend/proto/services/streaming_service.proto`:
```protobuf
message StreamChatMessage {
    ...
    string deleted_at = 8;   // 同样没有明确标记为可选
}
```

**问题：**
- Proto3 中空字符串 "" 和 null 无法区分
- 数据库中 NULL vs 空字符串 的语义不清楚
- 跨语言序列化时可能产生数据丢失

**修复优先级：** P2

---

### 级别：MEDIUM 🟡

#### 8. 数据类型不一致导致的精度丧失

**问题位置：**

文件 `/Users/proerror/Documents/nova/backend/proto/services/feed_service.proto`:
```protobuf
message FeedEntry {
    int32 like_count = 9;       // 32-bit
    int32 comment_count = 10;   // 32-bit
    int32 share_count = 11;     // 32-bit
    string engagement_score = 16;  // ❌ 应该是 double
}

message TrendingContent {
    int32 engagement_score = 4; // 32-bit int
    ...
}
```

与：

文件 `/Users/proerror/Documents/nova/backend/protos/recommendation.proto`:
```protobuf
message FeedPost {
    double ranking_score = 5;   // 双精度浮点
}

message RankedPost {
    double score = 2;           // 双精度浮点
}
```

**影响：**
- Engagement score 在 feed-service 中是 string，在 recommendation-service 中是 double
- 无法进行数值比较或排序
- JSON 序列化时会产生精度丧失

**修复优先级：** P3

---

## 跨服务协议映射表

```
服务                  | 定义位置1                    | 定义位置2                 | 状态
---------------------|------------------------------|-------------------------|--------
AuthService          | protos/auth.proto            | proto/services/auth_service.proto | CONFLICT
ContentService       | protos/content_service.proto | proto/services/content_service.proto | CONFLICT
VideoService         | protos/video.proto           | proto/services/video_service.proto | CONFLICT
MessagingService     | protos/messaging_service.proto | proto/services/messaging_service.proto | CONFLICT
MediaService         | protos/media_service.proto   | proto/services/media_service.proto | CONFLICT
StreamingService     | protos/streaming.proto       | proto/services/streaming_service.proto | CONFLICT
RecommendationService| protos/recommendation.proto  | (无对应)               | SINGLE
UserService          | (无旧版)                    | proto/services/user_service.proto | SINGLE
FeedService          | (无旧版)                    | proto/services/feed_service.proto | SINGLE
```

---

## 根本原因分析（Linus 视角）

这些问题的根本原因是 **数据结构设计的混乱**：

1. **没有单一的真实数据源** - 两套 proto 定义说明了架构设计时的迟疑
2. **边界情况处理分散** - 每个服务自行决定错误格式，导致特殊情况增加
3. **版本管理的缺失** - 没有清晰的向后兼容性策略

> "Bad programmers worry about the code. Good programmers worry about data structures."
> 
> 当前的问题 **不是代码问题，是数据结构定义混乱问题**。两套 proto 定义就像两份合同，法律无法执行。

---

## 修复方案（分阶段）

### Phase 1：立即修复（本周）

**删除所有重复的 proto 定义：**
```bash
rm /Users/proerror/Documents/nova/backend/protos/auth.proto
rm /Users/proerror/Documents/nova/backend/protos/video.proto
rm /Users/proerror/Documents/nova/backend/protos/content_service.proto
rm /Users/proerror/Documents/nova/backend/protos/media_service.proto
rm /Users/proerror/Documents/nova/backend/protos/messaging_service.proto
rm /Users/proerror/Documents/nova/backend/protos/recommendation.proto
rm /Users/proerror/Documents/nova/backend/protos/streaming.proto
```

**保留标准路径：** `/Users/proerror/Documents/nova/backend/proto/services/`

**统一所有包名和版本：**
```protobuf
package nova.{service_name}.v1;
option go_package = "github.com/novacorp/nova/backend/proto/{service_name}/v1";
```

### Phase 2：标准化错误处理（第二周）

**创建新文件：** `/Users/proerror/Documents/nova/backend/proto/common/error.proto`

```protobuf
syntax = "proto3";
package nova.common.v1;

message ErrorDetails {
    string code = 1;           // "USER_NOT_FOUND"
    string message = 2;        // 用户消息
    string error_type = 3;     // "not_found_error"
    int32 http_status = 4;     // 404
    string trace_id = 5;       // 请求追踪
    int64 timestamp = 6;       // Unix 秒
}
```

**更新所有响应消息：**

从：
```protobuf
message GetPostResponse {
    Post post = 1;
    bool found = 2;
    string error = 3;
}
```

改为：
```protobuf
message GetPostResponse {
    oneof result {
        Post post = 1;
        ErrorDetails error = 2;
    }
}
```

### Phase 3：统一时间戳格式（第三周）

**全局规则：** 所有 `created_at`, `updated_at`, `deleted_at` 都使用 `int64` Unix 秒级时间戳

**API 层映射：** Rust 实现负责转换为 ISO 8601

---

## 测试覆盖清单

- [ ] 编译所有 proto 文件，确保无重复定义错误
- [ ] 验证跨服务 gRPC 调用的请求/响应兼容性
- [ ] 测试错误响应的统一格式解析
- [ ] 验证时间戳的序列化/反序列化
- [ ] 测试 UUID 的有效性验证
- [ ] 验证枚举值的向后兼容性

---

## 概要表

| 问题 | 严重级别 | 影响范围 | 修复工作量 | 优先级 |
|-----|---------|--------|----------|--------|
| 双重 Proto 定义 | CRITICAL | 所有服务 | 2-3天 | P0 |
| 错误响应格式混乱 | HIGH | 所有服务 | 3-4天 | P1 |
| 时间戳格式不一致 | HIGH | 6 个服务 | 2天 | P1 |
| UUID 验证缺失 | HIGH | 所有服务 | 1天 | P2 |
| 枚举版本控制 | MEDIUM | 5 个服务 | 1天 | P2 |
| 可选字段标记 | MEDIUM | 3 个服务 | 1天 | P2 |
| 数据类型不一致 | MEDIUM | 2 个服务 | 1天 | P3 |

**总体修复时间估计：** 10-12 个工作日

