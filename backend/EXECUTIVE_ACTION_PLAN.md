# Nova微服务迁移：执行行动计划

## 核心诊断

**你的gRPC代理策略是对的，但是卡在了第一步：服务器根本没启动。**

## 当前状态（红绿灯）

| 组件 | 状态 | 问题 |
|-----|------|------|
| Proto定义 | 🟢 完成 | recommendation/video/streaming.proto已定义 |
| servers.rs实现 | 🟡 占位符 | 结构存在但返回假数据 |
| user-service main.rs | 🔴 **阻塞** | gRPC服务器没启动 |
| media-service | 🟡 混乱 | 有实现但架构不统一 |
| video-service | 🔴 空壳 | 只有框架 |
| streaming-service | 🔴 空壳 | 只有proto |
| recommendation-service | 🔴 空壳 | 只有proto |

## 本周必须完成的3件事（P0）

### 任务1：启动user-service的gRPC服务器

**文件**：`/backend/user-service/src/main.rs`

**问题**：第1,013行的main函数只启动了HTTP服务器（actix-web），gRPC服务器的启动代码不存在。

**解决方案**：在main.rs中添加gRPC服务器启动：

```rust
// 在HttpServer::new(...).bind(...).run() 之前添加

use user_service::grpc::{
    nova::recommendation::v1::recommendation_service_server::RecommendationServiceServer,
    nova::video::v1::video_service_server::VideoServiceServer,
    nova::streaming::v1::streaming_service_server::StreamingServiceServer,
};
use user_service::grpc::servers::{RecommendationServer, VideoServer, StreamingServer};

// 创建gRPC服务器实例（需要传递依赖）
let recommendation_server = RecommendationServer::new(
    db_pool.clone(),
    redis_client.clone(),
    clickhouse_client.clone(),
);
let video_server = VideoServer::new(
    db_pool.clone(),
    s3_service.clone(),
    job_sender.clone(), // 用于转码任务
);
let streaming_server = StreamingServer::new(
    db_pool.clone(),
    redis_client.clone(),
    stream_service.clone(),
);

// 启动3个gRPC服务器在不同端口
let grpc_rec_addr = "0.0.0.0:50051".parse().unwrap();
let grpc_video_addr = "0.0.0.0:50052".parse().unwrap();
let grpc_streaming_addr = "0.0.0.0:50053".parse().unwrap();

tokio::spawn(async move {
    tracing::info!("Starting RecommendationService gRPC server on :50051");
    tonic::transport::Server::builder()
        .add_service(RecommendationServiceServer::new(recommendation_server))
        .serve(grpc_rec_addr)
        .await
        .expect("gRPC server failed");
});

tokio::spawn(async move {
    tracing::info!("Starting VideoService gRPC server on :50052");
    tonic::transport::Server::builder()
        .add_service(VideoServiceServer::new(video_server))
        .serve(grpc_video_addr)
        .await
        .expect("gRPC server failed");
});

tokio::spawn(async move {
    tracing::info!("Starting StreamingService gRPC server on :50053");
    tonic::transport::Server::builder()
        .add_service(StreamingServiceServer::new(streaming_server))
        .serve(grpc_streaming_addr)
        .await
        .expect("gRPC server failed");
});

// 然后才是HTTP服务器
let server = HttpServer::new(move || { ... }).bind(...).run();
```

**验收标准**：
```bash
# 启动user-service后，应该看到3个gRPC服务器启动日志
cargo run --bin user-service

# 输出应该包含：
# Starting RecommendationService gRPC server on :50051
# Starting VideoService gRPC server on :50052
# Starting StreamingService gRPC server on :50053
```

---

### 任务2：修改servers.rs连接到现有业务逻辑

**文件**：`/backend/user-service/src/grpc/servers.rs`

**问题**：所有方法都返回假数据（空数组、假UUID）。

**解决方案**：

#### 2.1 修改RecommendationServer结构
```rust
// 当前：
pub struct RecommendationServer;

// 修改为：
pub struct RecommendationServer {
    db_pool: sqlx::PgPool,
    redis_client: redis::Client,
    ch_client: ClickHouseClient,
}

impl RecommendationServer {
    pub fn new(
        db_pool: sqlx::PgPool,
        redis_client: redis::Client,
        ch_client: ClickHouseClient,
    ) -> Self {
        Self { db_pool, redis_client, ch_client }
    }
}
```

#### 2.2 实现get_feed方法（示例）
```rust
async fn get_feed(
    &self,
    request: tonic::Request<GetFeedRequest>,
) -> Result<Response<GetFeedResponse>, Status> {
    let req = request.into_inner();

    // 解析user_id（从metadata获取或req中）
    let user_id = Uuid::parse_str(&req.user_id)
        .map_err(|_| Status::invalid_argument("Invalid user_id"))?;

    // 调用现有的feed逻辑（handlers/feed.rs）
    // 注意：你需要创建一个新的内部函数或重构现有handler
    let posts = crate::handlers::feed::get_feed_posts(
        &self.db_pool,
        &self.ch_client,
        user_id,
        req.limit as i64,
        req.cursor.as_deref(),
        req.algorithm.as_deref(),
    ).await.map_err(|e| {
        tracing::error!("Failed to get feed: {}", e);
        Status::internal("Failed to get feed")
    })?;

    // 转换为proto格式
    let proto_posts = posts.into_iter().map(|post| {
        FeedPost {
            id: post.id.to_string(),
            user_id: post.user_id.to_string(),
            content: post.content,
            // ... 其他字段
        }
    }).collect();

    Ok(Response::new(GetFeedResponse {
        posts: proto_posts,
        next_cursor: "...".to_string(), // 从查询结果计算
        has_more: posts.len() >= req.limit as usize,
    }))
}
```

#### 2.3 同样修改VideoServer和StreamingServer
（类似的模式：添加依赖 → 调用现有handlers → 转换数据格式）

**验收标准**：
```bash
# 使用grpcurl测试
grpcurl -plaintext -d '{"user_id": "test-uuid", "limit": 10}' \
    localhost:50051 nova.recommendation.v1.RecommendationService/GetFeed

# 应该返回实际数据，而不是空数组
```

---

### 任务3：验证video-service能通过gRPC工作

**文件**：`/backend/video-service/src/handlers/mod.rs`

**当前状态**：video-service有gRPC客户端，但HTTP handlers没有使用它。

**解决方案**：

```rust
// video-service/src/handlers/videos.rs

use crate::grpc::VideoGrpcClient;

pub async fn list_videos(
    state: web::Data<AppState>,
    query: web::Query<ListVideosQuery>,
) -> Result<HttpResponse, actix_web::Error> {
    // 调用user-service的gRPC
    let grpc_req = nova::video::v1::ListVideosRequest {
        user_id: query.user_id.clone(),
        limit: query.limit.unwrap_or(20),
        cursor: query.cursor.clone().unwrap_or_default(),
    };

    let response = state.grpc_client
        .list_videos(grpc_req)
        .await
        .map_err(|e| {
            tracing::error!("gRPC call failed: {}", e);
            actix_web::error::ErrorInternalServerError("Service unavailable")
        })?;

    // 转换gRPC响应为HTTP JSON
    let videos: Vec<VideoDto> = response.into_inner()
        .videos
        .into_iter()
        .map(|v| VideoDto {
            id: v.id,
            title: v.title,
            // ... 其他字段
        })
        .collect();

    Ok(HttpResponse::Ok().json(videos))
}
```

**验收标准**：
```bash
# 启动user-service（:8080, gRPC :50052）
cargo run --bin user-service

# 启动video-service（:8083）
cd video-service && cargo run

# 测试HTTP端点
curl http://localhost:8083/api/v1/videos?user_id=test

# 应该返回实际数据（来自user-service的gRPC）
```

---

## 下周的工作（P1）

### 任务4：统一media-service架构
- 移除media-service的独立db_pool
- 改为通过gRPC调用user-service（如果需要user数据）
- 或者保留独立但明确服务边界

### 任务5：迁移video handlers到video-service
- 将user-service/handlers/videos.rs逻辑移到video-service
- 保留user-service的gRPC服务器（向后兼容）
- 使用feature flag切换流量

---

## 关键架构决策（本周需要确认）

### 决策1：Job Queue在哪里？
**问题**：video转码需要异步任务队列。

**选项**：
- A. 保留在user-service（video-service通过gRPC提交job）
- B. 迁移到video-service（独立job queue）

**建议**：短期选A（简单），长期选B（独立）。

**本周行动**：
- 先用A（video-service → gRPC → user-service → job_queue）
- 验证可行性
- 下周再考虑B

### 决策2：数据库连接
**问题**：每个服务需要自己的db_pool吗？

**选项**：
- A. 共享user-service的db_pool（通过gRPC）
- B. 每个服务独立连接PostgreSQL

**建议**：短期选A（零迁移），长期选B（独立）。

**本周行动**：
- 所有数据访问通过user-service的gRPC
- 监控性能（如果gRPC成为瓶颈，下周改为B）

### 决策3：Redis使用
**问题**：缓存和限流需要Redis。

**选项**：
- A. 共享Redis（不同namespace）
- B. 每个服务独立Redis

**建议**：短期选A（简单），长期选B（隔离）。

**本周行动**：
- 所有服务连接同一个Redis
- 使用namespace区分（video:*, streaming:*, etc.）

---

## 错误处理指南

### 错误1：编译失败 - 找不到模块
```
error[E0433]: failed to resolve: use of undeclared crate or module `nova`
```

**解决**：检查build.rs是否正确编译proto文件。

```rust
// user-service/build.rs
fn main() -> Result<(), Box<dyn std::error::Error>> {
    tonic_build::configure()
        .build_server(true)
        .build_client(false) // user-service只需要server
        .compile(
            &[
                "../protos/recommendation.proto",
                "../protos/video.proto",
                "../protos/streaming.proto",
            ],
            &["../protos"],
        )?;
    Ok(())
}
```

### 错误2：运行时错误 - gRPC连接失败
```
Error: transport error: Connection refused (os error 61)
```

**解决**：确认user-service的gRPC服务器已启动。

```bash
# 检查端口监听
lsof -i :50051
lsof -i :50052
lsof -i :50053

# 应该看到user-service进程
```

### 错误3：gRPC返回空数据
```
Response: {"posts": [], "next_cursor": "", "has_more": false}
```

**解决**：servers.rs的实现还是占位符，需要连接到实际业务逻辑（任务2）。

---

## 验收测试脚本

创建一个测试脚本验证整个流程：

```bash
#!/bin/bash
# test_grpc_integration.sh

set -e

echo "=== Testing Nova Microservices Integration ==="

# 1. 启动user-service（后台）
echo "Starting user-service..."
cd /Users/proerror/Documents/nova/backend
cargo run --bin user-service &
USER_SERVICE_PID=$!
sleep 10

# 2. 检查gRPC服务器端口
echo "Checking gRPC ports..."
lsof -i :50051 || { echo "RecommendationService not running"; exit 1; }
lsof -i :50052 || { echo "VideoService not running"; exit 1; }
lsof -i :50053 || { echo "StreamingService not running"; exit 1; }

# 3. 启动video-service（后台）
echo "Starting video-service..."
cd video-service
cargo run &
VIDEO_SERVICE_PID=$!
sleep 5

# 4. 测试HTTP→gRPC→user-service流程
echo "Testing video-service HTTP endpoint..."
RESPONSE=$(curl -s http://localhost:8083/api/v1/videos?user_id=test-user)
echo "Response: $RESPONSE"

# 检查是否返回数据（不是空数组）
if echo "$RESPONSE" | grep -q '"videos":\[\]'; then
    echo "ERROR: Empty response (gRPC not working)"
    exit 1
fi

echo "SUCCESS: Integration test passed"

# 清理
kill $USER_SERVICE_PID $VIDEO_SERVICE_PID
```

---

## 成功标准（本周结束）

- [ ] user-service启动时显示3个gRPC服务器日志
- [ ] grpcurl能连接到:50051/:50052/:50053
- [ ] video-service的HTTP端点返回实际数据（通过gRPC）
- [ ] 响应时间< 100ms（本地测试）
- [ ] 零错误日志

---

## 如果遇到阻塞

### 阻塞1：不知道如何传递db_pool到servers.rs
**解决**：参考media-service/src/main.rs的做法。

### 阻塞2：handlers代码太复杂，不知道如何提取
**解决**：先创建简单的包装函数，逐步重构。

```rust
// 示例：在handlers/feed.rs中添加
pub async fn get_feed_posts_internal(
    db_pool: &sqlx::PgPool,
    ch_client: &ClickHouseClient,
    user_id: Uuid,
    limit: i64,
    cursor: Option<&str>,
    algorithm: Option<&str>,
) -> Result<Vec<Post>, crate::error::Error> {
    // 现有逻辑复制过来
    // 或者调用现有函数但避免HTTP依赖
}
```

### 阻塞3：gRPC编译错误太多
**解决**：先让一个方法工作，其他方法保持占位符。

```rust
// 先实现get_feed，其他方法返回unimplemented
async fn rank_posts(&self, _req: Request<RankPostsRequest>)
    -> Result<Response<RankPostsResponse>, Status> {
    Err(Status::unimplemented("Coming soon"))
}
```

---

## 本周的Linus式检查清单

每天下班前问自己：

- [ ] 今天的改动让系统更能工作了吗？
- [ ] 我添加的代码是必要的吗？
- [ ] 我解决了实际问题还是假想问题？
- [ ] 如果现在推送代码，会破坏什么吗？

**记住**：
> "先让它工作，再让它正确，最后让它快。"

本周目标：**让它工作**。

不要在本周做的事情：
- ❌ 重构现有代码
- ❌ 优化性能
- ❌ 设计数据库分离
- ❌ 实现所有gRPC方法

只做这3件事：
1. ✅ 启动gRPC服务器
2. ✅ 连接现有业务逻辑
3. ✅ 验证端到端流程

---

## 联系方式（如果需要讨论）

如果遇到技术阻塞或需要架构决策，记录问题：

1. 问题描述（具体的错误消息或行为）
2. 你尝试过的解决方案
3. 你认为的根本原因

然后我们可以快速讨论。

---

**开始执行。现在。**
