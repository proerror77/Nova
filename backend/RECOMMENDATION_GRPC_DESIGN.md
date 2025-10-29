# Recommendation Service gRPC调用设计

## 概述
recommendation-service作为独立服务，需要通过gRPC调用其他服务获取必要数据。

## gRPC客户端架构

```
recommendation-service
    │
    ├─► ContentServiceClient (content-service:8082)
    │   └─ GetFeed
    │   └─ InvalidateFeedEvent
    │
    ├─► UserServiceClient (user-service:8080)
    │   ├─ GetUserProfile
    │   ├─ GetUserFollows
    │   └─ GetUserLikes
    │
    └─► MediaServiceClient (media-service:8083)
        ├─ GetPostMetadata
        └─ GetVideoMetadata
```

## 客户端实现

### 1. ContentServiceClient
**用途**: Feed推荐和缓存失效

#### 方法定义
```rust
pub struct ContentServiceClient {
    client: content_service_client::ContentServiceClient<Channel>,
}

impl ContentServiceClient {
    // 获取用户feed
    pub async fn get_feed(&self, request: GetFeedRequest)
        -> Result<GetFeedResponse, Status>;

    // 使feed缓存失效
    pub async fn invalidate_feed_event(&self, request: InvalidateFeedEventRequest)
        -> Result<InvalidateFeedEventResponse, Status>;
}
```

#### Proto定义（需要从content-service同步）
```protobuf
service ContentService {
  rpc GetFeed (GetFeedRequest) returns (GetFeedResponse);
  rpc InvalidateFeedEvent (InvalidateFeedEventRequest) returns (InvalidateFeedEventResponse);
}

message GetFeedRequest {
  string user_id = 1;
  string algo = 2;  // "ch" or "time"
  uint32 limit = 3;
  string cursor = 4;
}

message GetFeedResponse {
  repeated string post_ids = 1;
  string cursor = 2;
  bool has_more = 3;
  uint32 total_count = 4;
}
```

### 2. UserServiceClient
**用途**: 获取用户数据用于ranking

#### 方法定义
```rust
pub struct UserServiceClient {
    client: user_service_client::UserServiceClient<Channel>,
}

impl UserServiceClient {
    // 获取用户资料
    pub async fn get_user_profile(&self, user_id: Uuid)
        -> Result<UserProfile, Status>;

    // 获取用户关注列表
    pub async fn get_user_follows(&self, user_id: Uuid, limit: usize)
        -> Result<Vec<Uuid>, Status>;

    // 获取用户点赞历史
    pub async fn get_user_likes(&self, user_id: Uuid, limit: usize)
        -> Result<Vec<Uuid>, Status>;

    // 批量获取用户资料（用于ranking）
    pub async fn batch_get_users(&self, user_ids: Vec<Uuid>)
        -> Result<Vec<UserProfile>, Status>;
}
```

#### Proto定义（待添加）
```protobuf
service UserService {
  rpc GetUserProfile (GetUserProfileRequest) returns (UserProfile);
  rpc GetUserFollows (GetUserFollowsRequest) returns (UserFollowsResponse);
  rpc GetUserLikes (GetUserLikesRequest) returns (UserLikesResponse);
  rpc BatchGetUsers (BatchGetUsersRequest) returns (BatchGetUsersResponse);
}

message UserProfile {
  string user_id = 1;
  string username = 2;
  string display_name = 3;
  int64 follower_count = 4;
  int64 following_count = 5;
  string avatar_url = 6;
}
```

### 3. MediaServiceClient
**用途**: 获取帖子和视频元数据用于ranking

#### 方法定义
```rust
pub struct MediaServiceClient {
    client: media_service_client::MediaServiceClient<Channel>,
}

impl MediaServiceClient {
    // 获取帖子元数据
    pub async fn get_post_metadata(&self, post_id: Uuid)
        -> Result<PostMetadata, Status>;

    // 批量获取帖子元数据（用于ranking）
    pub async fn batch_get_posts(&self, post_ids: Vec<Uuid>)
        -> Result<Vec<PostMetadata>, Status>;

    // 获取视频元数据
    pub async fn get_video_metadata(&self, video_id: Uuid)
        -> Result<VideoMetadata, Status>;
}
```

#### Proto定义（待添加）
```protobuf
service MediaService {
  rpc GetPostMetadata (GetPostMetadataRequest) returns (PostMetadata);
  rpc BatchGetPosts (BatchGetPostsRequest) returns (BatchGetPostsResponse);
  rpc GetVideoMetadata (GetVideoMetadataRequest) returns (VideoMetadata);
}

message PostMetadata {
  string post_id = 1;
  string user_id = 2;
  string content = 3;
  int64 like_count = 4;
  int64 comment_count = 5;
  int64 share_count = 6;
  int64 created_at = 7;
  repeated string media_urls = 8;
}
```

## 调用流程

### Discover Handler流程
```
Client Request
    ↓
GET /api/v1/discover/suggested-users
    ↓
DiscoverHandler
    ↓
Neo4j GraphService (本地)
    → 查询二度好友关系
    → 返回 UserWithScore
    ↓
Redis Cache (本地)
    → 缓存结果
    ↓
Response to Client
```

**依赖**: 无gRPC调用，使用本地Neo4j和Redis

### Feed Handler流程
```
Client Request
    ↓
GET /api/v1/feed?algo=ch&limit=20
    ↓
FeedHandler
    ↓
ContentServiceClient.get_feed() [gRPC]
    → content-service:8082
    → 返回 post_ids
    ↓
Response to Client
```

**gRPC调用**: 1次（ContentServiceClient）

### Trending Handler流程
```
Client Request
    ↓
GET /api/v1/trending/videos?time_window=24h
    ↓
TrendingHandler
    ↓
ClickHouse TrendingService (本地)
    → 聚合engagement事件
    → 计算trending分数
    ↓
Redis Cache (本地)
    → 缓存trending结果
    ↓
Response to Client
```

**依赖**: 无gRPC调用，使用本地ClickHouse和Redis

### Ranking Engine流程（待实现）
```
Client Request
    ↓
POST /api/v1/recommendations/rank
    ↓
RankingHandler
    ↓
UserServiceClient.get_user_profile() [gRPC]
    → 获取当前用户资料
    ↓
UserServiceClient.get_user_follows() [gRPC]
    → 获取用户关注列表
    ↓
MediaServiceClient.batch_get_posts() [gRPC]
    → 批量获取待排序帖子元数据
    ↓
RankingEngine (本地)
    → 特征提取
    → ONNX模型推理
    → 计算相关性分数
    ↓
Response to Client (排序后的post_ids)
```

**gRPC调用**: 3次（UserService x2, MediaService x1）

## 配置

### 环境变量
```bash
# Content Service
CONTENT_SERVICE_URL=http://content-service:8082

# User Service
USER_SERVICE_URL=http://user-service:8080

# Media Service
MEDIA_SERVICE_URL=http://media-service:8083

# gRPC超时配置
GRPC_TIMEOUT_SECS=30
GRPC_MAX_RETRIES=3
GRPC_RETRY_DELAY_MS=100
```

### 配置结构
```rust
#[derive(Debug, Clone, Deserialize)]
pub struct GrpcConfig {
    pub content_service_url: String,
    pub user_service_url: String,
    pub media_service_url: String,
    pub timeout_secs: u64,
    pub max_retries: u32,
    pub retry_delay_ms: u64,
}
```

## 错误处理

### gRPC错误映射
```rust
impl From<tonic::Status> for AppError {
    fn from(status: tonic::Status) -> Self {
        match status.code() {
            tonic::Code::NotFound =>
                AppError::NotFound(status.message().to_string()),
            tonic::Code::InvalidArgument =>
                AppError::BadRequest(status.message().to_string()),
            tonic::Code::Unauthenticated =>
                AppError::Authentication(status.message().to_string()),
            tonic::Code::PermissionDenied =>
                AppError::Authorization(status.message().to_string()),
            tonic::Code::Unavailable =>
                AppError::ServiceUnavailable(status.message().to_string()),
            _ =>
                AppError::Internal(format!("gRPC error: {}", status)),
        }
    }
}
```

### 重试策略
```rust
pub async fn call_with_retry<F, T>(
    func: F,
    max_retries: u32,
    delay_ms: u64,
) -> Result<T>
where
    F: Fn() -> BoxFuture<'static, Result<T, tonic::Status>>,
{
    let mut attempts = 0;
    loop {
        match func().await {
            Ok(result) => return Ok(result),
            Err(e) if should_retry(&e) && attempts < max_retries => {
                attempts += 1;
                tokio::time::sleep(Duration::from_millis(delay_ms)).await;
            }
            Err(e) => return Err(AppError::from(e)),
        }
    }
}

fn should_retry(status: &tonic::Status) -> bool {
    matches!(
        status.code(),
        tonic::Code::Unavailable | tonic::Code::DeadlineExceeded
    )
}
```

## 性能优化

### 1. 连接池
```rust
// 使用Arc + Mutex共享client实例
pub struct ClientPool {
    content_client: Arc<Mutex<ContentServiceClient>>,
    user_client: Arc<Mutex<UserServiceClient>>,
    media_client: Arc<Mutex<MediaServiceClient>>,
}
```

### 2. 批量调用
```rust
// 避免N+1问题，使用批量API
let user_ids: Vec<Uuid> = posts.iter().map(|p| p.user_id).collect();
let users = user_client.batch_get_users(user_ids).await?;
```

### 3. 并发调用
```rust
// 使用tokio::join!并行调用多个服务
let (user_result, posts_result) = tokio::join!(
    user_client.get_user_profile(user_id),
    media_client.batch_get_posts(post_ids),
);
```

### 4. 缓存策略
```rust
// 在recommendation-service本地缓存常用数据
// - 用户资料缓存（TTL: 5分钟）
// - 帖子元数据缓存（TTL: 1分钟）
// - 关注列表缓存（TTL: 10分钟）
```

## 监控指标

### gRPC调用Metrics
```rust
// Prometheus metrics
lazy_static! {
    static ref GRPC_CALL_DURATION: HistogramVec = register_histogram_vec!(
        "grpc_call_duration_seconds",
        "gRPC call duration",
        &["service", "method"]
    ).unwrap();

    static ref GRPC_CALL_ERRORS: CounterVec = register_counter_vec!(
        "grpc_call_errors_total",
        "gRPC call errors",
        &["service", "method", "code"]
    ).unwrap();
}
```

### 健康检查
```rust
// 检查所有gRPC服务是否可达
pub async fn health_check() -> Result<HealthStatus> {
    let content_ok = content_client.ping().await.is_ok();
    let user_ok = user_client.ping().await.is_ok();
    let media_ok = media_client.ping().await.is_ok();

    Ok(HealthStatus {
        content_service: content_ok,
        user_service: user_ok,
        media_service: media_ok,
        overall: content_ok && user_ok && media_ok,
    })
}
```

## 实施计划

### Phase 1: 基础框架（1周）
- [x] 创建ContentServiceClient基础结构
- [x] 创建proto占位符
- [ ] 从content-service同步真实proto
- [ ] 测试ContentServiceClient连接

### Phase 2: 扩展客户端（2周）
- [ ] 实现UserServiceClient
- [ ] 实现MediaServiceClient
- [ ] 添加重试和超时逻辑
- [ ] 添加监控metrics

### Phase 3: 集成Ranking（2周）
- [ ] 实现批量数据获取
- [ ] 集成ONNX推理
- [ ] 性能优化和缓存
- [ ] 端到端测试

## 测试策略

### 单元测试
```rust
#[tokio::test]
async fn test_content_client_get_feed() {
    let client = ContentServiceClient::new("http://localhost:8082").await.unwrap();
    let request = GetFeedRequest {
        user_id: "test-user".to_string(),
        algo: "ch".to_string(),
        limit: 10,
        cursor: String::new(),
    };
    let response = client.get_feed(request).await.unwrap();
    assert!(!response.post_ids.is_empty());
}
```

### 集成测试
```bash
# docker-compose测试环境
docker-compose -f docker-compose.test.yml up -d
cargo test --test integration_grpc_clients
```

### 负载测试
```bash
# 使用ghz进行gRPC压力测试
ghz --insecure --proto=recommendation.proto \
    --call=nova.recommendation.v1.RecommendationService/GetFeed \
    -d '{"user_id":"test","algo":"ch","limit":20}' \
    -n 10000 -c 100 \
    localhost:50051
```

## 故障排查

### 常见问题

1. **连接超时**
   - 检查服务地址配置
   - 检查网络连通性
   - 增加GRPC_TIMEOUT_SECS

2. **序列化错误**
   - 验证proto版本一致性
   - 检查protobuf生成代码

3. **性能下降**
   - 启用连接池
   - 使用批量API
   - 添加本地缓存

## 总结

recommendation-service通过gRPC调用依赖以下服务：
- **content-service**: Feed数据（必须）
- **user-service**: 用户资料（ranking需要）
- **media-service**: 帖子元数据（ranking需要）

当前状态:
- ✅ ContentServiceClient框架已建立
- 🟡 Proto定义需要同步
- ⏳ UserServiceClient待实现
- ⏳ MediaServiceClient待实现

下一步: 从content-service提取真实proto文件并生成Rust代码。
