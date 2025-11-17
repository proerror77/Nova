# 数据所有权矩阵 (Data Ownership Matrix)

**Version**: 1.0
**Last Updated**: 2025-11-11
**Principle**: "每个数据实体只能有一个服务拥有写权限"

---

## 核心域划分 (Domain Boundaries)

### 1. Identity Domain (身份域)
**Service**: `identity-service` (原 auth-service + user-service（已淘汰）整合)
**Responsibility**: 用户身份、认证、授权、档案管理

| Data Entity | Table Name | Operations | Access Pattern |
|------------|------------|------------|----------------|
| Users | `users` | CREATE, UPDATE, DELETE | Owner: Write-only |
| Sessions | `sessions` | CREATE, UPDATE, DELETE | Owner: Write-only |
| Credentials | `credentials` | CREATE, UPDATE, DELETE | Owner: Write-only |
| Roles | `roles` | CREATE, UPDATE, DELETE | Owner: Write-only |
| Permissions | `permissions` | CREATE, UPDATE, DELETE | Owner: Write-only |
| UserRoles | `user_roles` | CREATE, UPDATE, DELETE | Owner: Write-only |
| RefreshTokens | `refresh_tokens` | CREATE, UPDATE, DELETE | Owner: Write-only |

**Exposed APIs**:
```proto
service IdentityService {
  rpc Authenticate(AuthRequest) returns (AuthResponse);
  rpc ValidateToken(TokenRequest) returns (TokenResponse);
  rpc RevokeToken(RevokeRequest) returns (RevokeResponse);
  rpc GetUser(GetUserRequest) returns (UserResponse);
  rpc UpdateUserProfile(UpdateProfileRequest) returns (ProfileResponse);
  rpc AssignRole(RoleAssignRequest) returns (RoleResponse);
}
```

---

### 2. Content Domain (内容域)
**Service**: `content-service`
**Responsibility**: 内容创建、管理、版本控制

| Data Entity | Table Name | Operations | Access Pattern |
|------------|------------|------------|----------------|
| Posts | `posts` | CREATE, UPDATE, DELETE | Owner: Write-only |
| Articles | `articles` | CREATE, UPDATE, DELETE | Owner: Write-only |
| Comments | `comments` | CREATE, UPDATE, DELETE | Owner: Write-only |
| ContentVersions | `content_versions` | CREATE, UPDATE | Owner: Write-only |
| ContentMeta | `content_metadata` | CREATE, UPDATE, DELETE | Owner: Write-only |
| Tags | `tags` | CREATE, UPDATE, DELETE | Owner: Write-only |
| ContentTags | `content_tags` | CREATE, UPDATE, DELETE | Owner: Write-only |

**Exposed APIs**:
```proto
service ContentService {
  rpc CreatePost(CreatePostRequest) returns (PostResponse);
  rpc UpdatePost(UpdatePostRequest) returns (PostResponse);
  rpc GetPost(GetPostRequest) returns (PostResponse);
  rpc ListPosts(ListPostsRequest) returns (PostsResponse);
  rpc AddComment(CommentRequest) returns (CommentResponse);
  rpc GetContentHistory(HistoryRequest) returns (HistoryResponse);
}
```

---

### 3. Social Domain (社交域)
**Service**: `social-service` (原 feed-service 重命名)
**Responsibility**: 社交关系、信息流、互动

| Data Entity | Table Name | Operations | Access Pattern |
|------------|------------|------------|----------------|
| Relationships | `relationships` | CREATE, UPDATE, DELETE | Owner: Write-only |
| Feeds | `feeds` | CREATE, UPDATE, DELETE | Owner: Write-only |
| Likes | `likes` | CREATE, DELETE | Owner: Write-only |
| Shares | `shares` | CREATE, DELETE | Owner: Write-only |
| Bookmarks | `bookmarks` | CREATE, DELETE | Owner: Write-only |
| Timeline | `timeline_events` | CREATE, UPDATE | Owner: Write-only |

**Exposed APIs**:
```proto
service SocialService {
  rpc Follow(FollowRequest) returns (FollowResponse);
  rpc Unfollow(UnfollowRequest) returns (UnfollowResponse);
  rpc GetFeed(FeedRequest) returns (FeedResponse);
  rpc LikeContent(LikeRequest) returns (LikeResponse);
  rpc ShareContent(ShareRequest) returns (ShareResponse);
  rpc GetTimeline(TimelineRequest) returns (TimelineResponse);
}
```

---

### 4. Media Domain (媒体域)
**Service**: `media-service` (合并 media + video + streaming)
**Responsibility**: 文件存储、媒体处理、元数据管理

| Data Entity | Table Name | Operations | Access Pattern |
|------------|------------|------------|----------------|
| MediaFiles | `media_files` | CREATE, UPDATE, DELETE | Owner: Write-only |
| MediaMeta | `media_metadata` | CREATE, UPDATE, DELETE | Owner: Write-only |
| Thumbnails | `thumbnails` | CREATE, UPDATE, DELETE | Owner: Write-only |
| Transcodes | `transcode_jobs` | CREATE, UPDATE, DELETE | Owner: Write-only |
| MediaVersions | `media_versions` | CREATE, UPDATE | Owner: Write-only |

**Exposed APIs**:
```proto
service MediaService {
  rpc UploadMedia(UploadRequest) returns (MediaResponse);
  rpc GetMedia(GetMediaRequest) returns (MediaResponse);
  rpc ProcessMedia(ProcessRequest) returns (ProcessResponse);
  rpc GenerateThumbnail(ThumbnailRequest) returns (ThumbnailResponse);
  rpc TranscodeVideo(TranscodeRequest) returns (TranscodeResponse);
}
```

---

### 5. Delivery Domain (分发域)
**Service**: `delivery-service` (原 cdn-service 扩展)
**Responsibility**: CDN分发、流媒体、缓存管理

| Data Entity | Table Name | Operations | Access Pattern |
|------------|------------|------------|----------------|
| CDNNodes | `cdn_nodes` | CREATE, UPDATE, DELETE | Owner: Write-only |
| CacheRules | `cache_rules` | CREATE, UPDATE, DELETE | Owner: Write-only |
| StreamingSessions | `streaming_sessions` | CREATE, UPDATE, DELETE | Owner: Write-only |
| DeliveryMetrics | `delivery_metrics` | CREATE, UPDATE | Owner: Write-only |
| EdgeLocations | `edge_locations` | CREATE, UPDATE, DELETE | Owner: Write-only |

**Exposed APIs**:
```proto
service DeliveryService {
  rpc GetStreamUrl(StreamRequest) returns (StreamResponse);
  rpc InvalidateCache(InvalidateRequest) returns (InvalidateResponse);
  rpc GetCDNStatus(StatusRequest) returns (StatusResponse);
  rpc StartStreaming(StartStreamRequest) returns (StreamResponse);
  rpc EndStreaming(EndStreamRequest) returns (EndResponse);
}
```

---

### 6. Communication Domain (通信域)
**Service**: `messaging-service` + `notification-service`
**Responsibility**: 实时聊天、推送通知、邮件短信

#### Messaging Service (实时通信)
| Data Entity | Table Name | Operations | Access Pattern |
|------------|------------|------------|----------------|
| Conversations | `conversations` | CREATE, UPDATE, DELETE | Owner: Write-only |
| Messages | `messages` | CREATE, UPDATE, DELETE | Owner: Write-only |
| MessageStatus | `message_status` | CREATE, UPDATE | Owner: Write-only |
| Participants | `participants` | CREATE, UPDATE, DELETE | Owner: Write-only |

#### Notification Service (异步通知)
| Data Entity | Table Name | Operations | Access Pattern |
|------------|------------|------------|----------------|
| Notifications | `notifications` | CREATE, UPDATE, DELETE | Owner: Write-only |
| EmailQueue | `email_queue` | CREATE, UPDATE, DELETE | Owner: Write-only |
| SMSQueue | `sms_queue` | CREATE, UPDATE, DELETE | Owner: Write-only |
| PushTokens | `push_tokens` | CREATE, UPDATE, DELETE | Owner: Write-only |
| NotificationPrefs | `notification_preferences` | CREATE, UPDATE, DELETE | Owner: Write-only |

---

### 7. Search Domain (搜索域) - Read Only
**Service**: `search-service`
**Responsibility**: 索引管理、搜索查询、建议

| Data Entity | Table Name | Operations | Access Pattern |
|------------|------------|------------|----------------|
| SearchIndex | `search_indices` | CREATE, UPDATE, DELETE | Owner: Write-only |
| Suggestions | `search_suggestions` | CREATE, UPDATE | Owner: Write-only |
| SearchHistory | `search_history` | CREATE | Owner: Write-only |
| SearchMetrics | `search_metrics` | CREATE, UPDATE | Owner: Write-only |

**Note**: Search Service 通过事件订阅其他服务的数据变更，构建只读投影。

---

### 8. Events Domain (事件域) - Technical Component
**Service**: `events-service`
**Responsibility**: 事件路由、分发、重试机制

| Data Entity | Table Name | Operations | Access Pattern |
|------------|------------|------------|----------------|
| Events | `domain_events` | CREATE | Owner: Write-only |
| EventHandlers | `event_handlers` | CREATE, UPDATE | Owner: Write-only |
| EventDeadLetter | `event_dead_letter` | CREATE, UPDATE | Owner: Write-only |
| EventSubscriptions | `event_subscriptions` | CREATE, UPDATE, DELETE | Owner: Write-only |

---

## 跨服务数据访问规则 (Cross-Service Data Access Rules)

### 规则 1: 禁止直接数据库访问
❌ **错误示例**:
```rust
// content-service 直接查询 users 表
let user = sqlx::query_as::<_, User>(
    "SELECT * FROM users WHERE id = $1"
)
.fetch_one(&pool)
.await?;
```

✅ **正确示例**:
```rust
// content-service 通过 gRPC 调用 identity-service
let user = identity_client
    .get_user(GetUserRequest {
        id: user_id.to_string()
    })
    .await?;
```

### 规则 2: 事件驱动的数据同步
```rust
// identity-service 发布用户创建事件
event_bus.publish(DomainEvent::UserCreated {
    user_id,
    username,
    email,
    created_at: Utc::now(),
}).await?;

// content-service 订阅并更新本地缓存
#[event_handler(topic = "user.created")]
async fn handle_user_created(event: UserCreatedEvent) {
    // 更新本地用户投影（只读）
    cache.set_user_projection(UserProjection {
        id: event.user_id,
        username: event.username,
    }).await?;
}
```

### 规则 3: 数据库约束强制执行
```sql
-- 为每个表添加服务所有权约束
ALTER TABLE users
ADD CONSTRAINT owned_by_identity
CHECK (service_owner = 'identity-service');

-- 创建审计触发器
CREATE TRIGGER audit_cross_service_access
BEFORE INSERT OR UPDATE OR DELETE ON users
FOR EACH ROW
EXECUTE FUNCTION verify_service_ownership();
```

---

## 数据一致性保证 (Data Consistency Guarantees)

### 1. 强一致性 (Within Service)
- 服务内部事务保证 ACID
- 使用数据库事务处理本地操作

### 2. 最终一致性 (Cross Service)
- 跨服务通过事件实现最终一致性
- 使用 Saga 模式处理分布式事务
- 实施补偿机制处理失败场景

### 3. 读取一致性策略
```rust
pub enum ConsistencyLevel {
    Strong,     // 直接从源服务读取
    Eventual,   // 从本地缓存读取
    Bounded,    // 容忍特定时间窗口的延迟
}
```

---

## 迁移计划 (Migration Plan)

### Phase 1: 立即执行 (P0)
1. **合并媒体服务** (Week 1)
   - media + video + streaming → media-service
   - cdn → delivery-service

2. **明确认证边界** (Week 1)
   - auth-service → identity-service (扩展功能)
  - user-service → 已完全移除，功能分別由 identity-service / social-service 承接

3. **创建数据所有权文档** (Complete)
   - 本文档作为团队参考

### Phase 2: 短期目标 (P1)
1. **实施服务调用审计** (Week 2)
   - 添加 gRPC 拦截器记录跨服务调用
   - 识别违反数据所有权的调用

2. **消除循环依赖** (Week 2-3)
   - 通过事件解耦服务间依赖
   - 重构同步调用为异步事件

3. **标准化事件模式** (Week 3)
   - 定义统一的事件格式
   - 实施事件版本管理

### Phase 3: 中期目标 (P2)
1. **数据库 Schema 重构** (Week 4-5)
   - 添加服务所有权字段
   - 实施数据库约束

2. **实施 CQRS** (Week 5-6)
   - 分离读写模型
   - 构建专用查询服务

3. **完善服务自治** (Week 6-7)
   - 独立部署能力
   - 故障隔离机制

---

## 验证检查清单 (Validation Checklist)

- [ ] 每个数据表有唯一的写入服务
- [ ] 没有服务间的循环依赖
- [ ] 所有跨服务通信通过 API 或事件
- [ ] 每个服务可以独立部署
- [ ] 服务故障不会级联影响其他服务
- [ ] 数据一致性策略明确定义
- [ ] 监控和告警覆盖所有服务边界

---

## 参考资料
- Domain-Driven Design by Eric Evans
- Building Microservices by Sam Newman
- Data Management in Microservices (Martin Fowler)
