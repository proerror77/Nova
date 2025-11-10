# REST vs gRPC 端点映射参考

这是所有服务的完整端点映射，便于快速查阅。

---

## Auth Service

**文件**: `/Users/proerror/Documents/nova/backend/auth-service/src/main.rs` (419 行)

| gRPC 方法 | REST 端点 | 对应状态 |
|-----------|----------|---------|
| Register | POST /api/v1/auth/register | ✅ |
| Login | POST /api/v1/auth/login | ✅ |
| Refresh | POST /api/v1/auth/refresh | ✅ |
| GetUser | ❌ | 仅 gRPC |
| GetUsersByIds | ❌ | 仅 gRPC (批量) |
| VerifyToken | ❌ | 仅 gRPC |
| CheckUserExists | ❌ | 仅 gRPC |
| GetUserByEmail | ❌ | 仅 gRPC |
| ListUsers | ❌ | 仅 gRPC |
| CheckPermission | ❌ | 仅 gRPC |
| GetUserPermissions | ❌ | 仅 gRPC |
| RecordFailedLogin | ❌ | 仅 gRPC |
| UpdateUserProfile | ❌ | 仅 gRPC |
| UpsertUserPublicKey | ❌ | 仅 gRPC |
| GetUserPublicKey | ❌ | 仅 gRPC |

**REST 额外端点** (无 gRPC 对应):
- POST /api/v1/auth/password-reset/request
- POST /api/v1/auth/logout
- POST /api/v1/auth/change-password
- POST /api/v1/oauth/start
- POST /api/v1/oauth/complete

---

## User Service

**文件**: `/Users/proerror/Documents/nova/backend/user-service/src/main.rs` (1,105 行)

| gRPC 方法 | REST 端点 | 对应状态 |
|-----------|----------|---------|
| GetUserProfile | GET /api/v1/users/{id} | ✅ |
| UpdateUserProfile | PATCH /api/v1/users/me | ✅ |
| FollowUser | POST /api/v1/users/{id}/follow | ✅ |
| UnfollowUser | DELETE /api/v1/users/{id}/follow | ✅ |
| BlockUser | POST /api/v1/users/{id}/block | ✅ |
| UnblockUser | DELETE /api/v1/users/{id}/block | ✅ |
| GetUserFollowers | GET /api/v1/users/{id}/followers | ✅ |
| GetUserFollowing | GET /api/v1/users/{id}/following | ✅ |
| GetUserSettings | ❌ | 仅 gRPC |
| UpdateUserSettings | ❌ | 仅 gRPC |
| GetUserProfilesByIds | ❌ | 仅 gRPC (批量) |
| CheckUserRelationship | ❌ | 仅 gRPC |
| SearchUsers | ❌ | 仅 gRPC |

**REST 额外端点** (无 gRPC 对应):
- GET /api/v1/users/me
- PUT /api/v1/users/me/public-key
- POST /api/v1/users/me/preferences/blocked-users/{id}
- DELETE /api/v1/users/me/preferences/blocked-users/{id}
- GET /api/v1/users/{id}/public-key

---

## Feed Service

**文件**: `/Users/proerror/Documents/nova/backend/feed-service/src/main.rs` (357 行)

| gRPC 方法 | REST 端点 | 对应状态 |
|-----------|----------|---------|
| GetFeed | GET /api/v1/feed | ✅ |
| GetTrending | GET /api/v1/trending | ✅ |
| GetPersonalizedFeed | POST /api/v1/feed/personalized | ✅ |
| ClearCache | DELETE /api/v1/feed/cache | ✅ |
| GetTrendingHashtags | ❌ | 仅 gRPC |
| GetTrendingUsers | ❌ | 仅 gRPC |
| GetRecommendations | ❌ | 仅 gRPC |

---

## Search Service

**文件**: `/Users/proerror/Documents/nova/backend/search-service/src/main.rs` (967 行)

| gRPC 方法 | REST 端点 | 对应状态 |
|-----------|----------|---------|
| Search | POST /api/v1/search/query | ✅ |
| GetSuggestions | GET /api/v1/search/suggestions | ✅ |
| AdvancedSearch | POST /api/v1/search/advanced | ✅ |
| GetTrending | GET /api/v1/search/trending | ✅ |
| ApplyFilters | POST /api/v1/search/filters | ✅ |
| SearchUsers | GET /api/v1/search/users | ✅ |
| SearchPosts | GET /api/v1/search/posts | ✅ |
| SearchHashtags | GET /api/v1/search/hashtags | ✅ |
| ReindexSearch | POST /api/v1/search/index/reindex | ✅ |
| ClearCache | DELETE /api/v1/search/cache | ✅ |

---

## Notification Service

**文件**: `/Users/proerror/Documents/nova/backend/notification-service/src/main.rs` (148 行)

| gRPC 方法 | REST 端점 | 对应状态 |
|-----------|----------|---------|
| GetNotifications | GET /api/v1/notifications | ✅ |
| MarkAsRead | POST /api/v1/notifications/mark-as-read | ✅ |
| GetUnreadCount | GET /api/v1/notifications/unread-count | ✅ |
| SendNotification | ❌ | 仅 gRPC |
| DeleteNotification | ❌ | 仅 gRPC |
| ClearAll | ❌ | 仅 gRPC |
| (+ 8 其他) | ❌ | 仅 gRPC |

---

## Messaging Service

**文件**: `/Users/proerror/Documents/nova/backend/messaging-service/src/main.rs` (254 行)

**状态**: 几乎完全是 gRPC！仅有 1 个 REST 端点

| REST 端点 | 用途 |
|----------|------|
| GET /health | 健康检查 (应转为 gRPC Health Check) |

**gRPC 方法** (28 个):
- SendMessage, GetConversations, GetMessages, UpdateMessage, DeleteMessage
- GetConversation, CreateConversation, MarkAsRead, GetUnreadCount
- SearchMessages, ArchiveConversation, PinMessage, TypingIndicator
- (+ 更多)

---

## Streaming Service

**文件**: `/Users/proerror/Documents/nova/backend/streaming-service/src/main.rs` (228 行)

| gRPC 方法 | REST 端点 | 对应状态 |
|-----------|----------|---------|
| StartStream | POST /api/v1/stream/start | ✅ |
| GetStreamStatus | GET /api/v1/stream/{stream_id}/status | ✅ |
| EndStream | POST /api/v1/stream/{stream_id}/end | ✅ |
| GetActiveStreams | ❌ | 仅 gRPC |
| SendHeartbeat | ❌ | 仅 gRPC |
| GetStreamHistory | ❌ | 仅 gRPC |
| GetStreamMetrics | ❌ | 仅 gRPC |

---

## CDN Service

**文件**: `/Users/proerror/Documents/nova/backend/cdn-service/src/main.rs` (127 行)

**状态**: 完全是 gRPC！仅有 1 个 REST 端点

| REST 端点 | 用途 |
|----------|------|
| GET /health | 健康检查 (应转为 gRPC Health Check) |

**gRPC 方法** (12 个):
- GetCdnUrl, PutObject, DeleteObject, GetObject, ListObjects
- GetObjectMetadata, UpdateObject, GetPresignedUrl, GetBucketStats
- ClearCache, GetCacheStatus, CreateBucket

---

## Events Service

**文件**: `/Users/proerror/Documents/nova/backend/events-service/src/main.rs` (141 行)

| gRPC 方法 | REST 端点 | 对应状态 |
|-----------|----------|---------|
| PublishEvent | POST /api/v1/events/publish | ✅ |
| GetEventStatus | GET /api/v1/events/status | ✅ |
| GetEventHistory | ❌ | 仅 gRPC |
| SubscribeToEvents | ❌ | 仅 gRPC (流) |
| ListEventTypes | ❌ | 仅 gRPC |
| GetEventMetrics | ❌ | 仅 gRPC |
| (+ 8 其他) | ❌ | 仅 gRPC |

---

## Content Service (REST-ONLY)

**文件**: `/Users/proerror/Documents/nova/backend/content-service/src/main.rs` (665 行)

**状态**: ❌ **无 gRPC 支持** (应该添加)

REST 端点 (22 个):
```
POST   /api/v1/posts
GET    /api/v1/posts/{id}
PATCH  /api/v1/posts/{id}
DELETE /api/v1/posts/{id}
POST   /api/v1/posts/{id}/like
DELETE /api/v1/posts/{id}/like
POST   /api/v1/posts/{id}/comments
GET    /api/v1/posts/{id}/comments
POST   /api/v1/comments/{id}/like
DELETE /api/v1/comments/{id}/like
GET    /api/v1/stories
POST   /api/v1/stories
DELETE /api/v1/stories/{id}
POST   /api/v1/bookmarks
GET    /api/v1/bookmarks
DELETE /api/v1/bookmarks/{id}
GET    /api/v1/drafts
POST   /api/v1/drafts
GET    /api/v1/notifications
POST   /api/v1/notifications/{id}/mark-read
GET    /api/v1/health
GET    /api/v1/openapi.json
```

---

## Media Service (REST-ONLY)

**文件**: `/Users/proerror/Documents/nova/backend/media-service/src/main.rs` (303 行)

**状态**: ❌ **无 gRPC 支持** (应该添加)

REST 端点 (26 个):
```
POST   /api/v1/media/upload
GET    /api/v1/media/{id}
DELETE /api/v1/media/{id}
POST   /api/v1/videos/upload
GET    /api/v1/videos/{id}
POST   /api/v1/videos/{id}/transcode
GET    /api/v1/videos/{id}/status
DELETE /api/v1/videos/{id}
(+ 更多文件/视频操作)
```

---

## Video Service (REST-ONLY)

**文件**: `/Users/proerror/Documents/nova/backend/video-service/src/main.rs` (57 行)

**状态**: ✓ 仅健康检查，可保持 REST

REST 端点:
```
GET    /health
```

---

## 汇总：冗余度最高的服务

### 完全冗余 (100% 对应)
- **Search Service**: 13 个 REST 端点 ↔ 10 个 gRPC 方法
- **User Service**: 18 个 REST 端点 ↔ 13 个 gRPC 方法
- **Feed Service**: 4 个 REST 端点 ↔ 7 个 gRPC 方法

### 大部分冗余 (>80% 对应)
- **Auth Service**: 8 个 REST 端点 ↔ 15 个 gRPC 方法
- **Streaming Service**: 3 个 REST 端点 ↔ 7 个 gRPC 方法

### 部分冗余 (>50% 对应)
- **Notification Service**: 3 个 REST 端点 ↔ 13 个 gRPC 方法
- **Events Service**: 2 个 REST 端点 ↔ 14 个 gRPC 方法

### 极低冗余 (<20% 对应)
- **Messaging Service**: 1 个 REST 端点 (健康检查) ↔ 28 个 gRPC 方法
- **CDN Service**: 1 个 REST 端点 (健康检查) ↔ 12 个 gRPC 方法

---

**生成时间**: 2025-11-10
