# Nova 微服务拆分实战分析

## 执行摘要

**核心问题**：Nova正在从单体user-service（51,273行）拆分为微服务架构，但存在关键阻塞问题。

**当前状态**：
- ✅ Proto文件定义完成（recommendation/video/streaming）
- ✅ 新服务已创建（media/video/streaming/recommendation）
- ✅ gRPC服务器实现（servers.rs）存在但是占位符
- ❌ **关键缺失**：user-service的main.rs没有启动gRPC服务器
- ❌ **关键缺失**：新服务的实现都是空壳，没有实际业务逻辑

**实际情况**：你走到了gRPC代理策略的第一步，但卡在了第二步。

---

## 当前架构分析

### 1. user-service 现状

**代码规模**：
- 总行数：51,273行
- TODO数量：64个

**核心依赖（强耦合）**：
```rust
// main.rs 初始化的关键基础设施
- PostgreSQL Pool (db_pool)          // 所有服务都需要
- Redis Client (redis_client)        // 缓存和限流
- Kafka Producer (event_producer)    // 事件驱动
- ClickHouse Client (ch_client)      // 分析和feed ranking
- Job Queue (job_queue)              // 异步任务（转码、邮件等）
- S3 Service (s3_service)            // 文件上传
- JWT Auth Middleware                // 身份验证
- Circuit Breakers                   // 容错
- Metrics (Prometheus)               // 监控
```

**关键服务**：
```rust
// 这些是需要迁移的核心业务逻辑
- VideoService                       // 7,634行（视频处理）
- StreamService                      // 1,000+行（直播）
- RankingEngine / FeedService        // 1,000+行（推荐算法）
- DeepLearningInferenceService       // ONNX模型推理
- TranscodingService                 // FFmpeg转码
```

**WebSocket状态**：
```rust
// streams_ws.rs 使用actix-ws
- StreamChatHandlerState             // 直播聊天状态
- ViewerCounter                      // 观众计数（Redis）
- 实时广播消息
```

### 2. 已创建的新服务

#### media-service（已运行）
```rust
// HTTP: :8082, gRPC: :9082
主要功能：
- 视频上传（presigned URL）
- Reels处理（短视频）
- 转码管道（ReelTranscodePipeline）

状态：✅ 已实现完整功能
问题：❌ 依然使用自己的数据库，与user-service没有通信
```

#### video-service（空壳）
```rust
// 连接到user-service的gRPC客户端
状态：❌ 只有HTTP→gRPC代理框架，没有实际实现
```

#### streaming-service（空壳）
```rust
状态：❌ 只有proto定义，没有实现
```

#### recommendation-service（空壳）
```rust
状态：❌ 只有proto定义，没有实现
```

---

## 关键问题（Linus式分析）

### 问题1：gRPC服务器没启动
**症状**：user-service/src/main.rs（1,013行）没有启动gRPC服务器的代码。

**根本问题**：
- servers.rs实现了`RecommendationServer`、`VideoServer`、`StreamingServer`
- 但是main.rs只启动了HTTP服务器（actix-web）
- 新服务的gRPC客户端无法连接

**Linus会说什么**：
> "你定义了接口但没有实现。这不是理论问题，是实际的编译和运行问题。"

**解决方案**：
```rust
// 在user-service/src/main.rs中添加
tokio::spawn(async move {
    // 启动3个gRPC服务器
    // :50051 - RecommendationService
    // :50052 - VideoService
    // :50053 - StreamingService
});
```

### 问题2：服务器实现是占位符
**症状**：servers.rs中所有方法都返回空数据或TODO注释。

**根本问题**：
- `get_feed()` → 返回空数组
- `upload_video()` → 返回假的UUID
- `start_stream()` → 返回假的stream_id

**解决方案**：需要连接到现有的handlers：
```rust
// 示例：RecommendationServer::get_feed
async fn get_feed(&self, req: GetFeedRequest) -> Result<Response<GetFeedResponse>> {
    // 调用现有的 handlers/feed.rs 中的逻辑
    let posts = handlers::feed::get_feed_internal(
        user_id,
        algorithm,
        limit,
        cursor,
        // 传递db_pool, redis_client等
    ).await?;

    Ok(Response::new(GetFeedResponse {
        posts: posts.into_iter().map(|p| convert_to_proto(p)).collect(),
        // ...
    }))
}
```

### 问题3：强耦合依赖没解决
**症状**：新服务需要访问user-service的所有依赖。

**根本问题**：
- Database Pool：每个服务需要自己的连接池还是共享user-service的？
- Redis Client：缓存和限流需要在哪里？
- Kafka Producer：事件发布在哪里？
- Job Queue：转码任务在哪里处理？

**当前状态**：
- media-service有自己的db_pool和redis_client（重复）
- video-service没有这些依赖（无法工作）
- streaming-service没有这些依赖（无法工作）

---

## Linus式决策：什么优先？

### "好品味"原则：消除特殊情况

**错误的做法**（你当前的状态）：
```
- media-service: 有自己的DB和Redis ❌
- video-service: 空壳，连接user-service gRPC ❌
- user-service: gRPC服务器没启动 ❌
```
结果：3种不同的架构模式，全都不能工作。

**正确的做法**（统一架构）：
选择一种模式，全部使用：

#### 方案A：共享数据库 + gRPC代理（Pragmatic）
```
新服务 → gRPC → user-service → 业务逻辑 → 共享DB

优点：
✅ 立即可用
✅ 零数据迁移
✅ 单一数据源
✅ 事务完整性

缺点：
❌ DB成为瓶颈
❌ 服务不是真正独立
```

#### 方案B：分库 + 事件驱动（理论完美）
```
新服务 → 自己的DB → Kafka事件同步

优点：
✅ 服务真正独立
✅ 可扩展性强

缺点：
❌ 需要迁移数据
❌ 需要事件溯源
❌ 最终一致性复杂
❌ 实施周期长（数月）
```

**Linus的选择**：方案A（Pragmatic）
> "解决实际问题，而不是假想的威胁。先让它工作，再优化。"

---

## 实用方案：3个月路线图

### 第1个月：修复基础架构（让它能运行）

#### Week 1-2: 启动gRPC服务器
**目标**：让user-service作为gRPC服务器运行。

**任务**：
1. 在user-service/src/main.rs中添加gRPC服务器启动代码
2. 传递必要的依赖（db_pool, redis_client等）到servers
3. 更新servers.rs连接到现有handlers
4. 端到端测试：新服务→gRPC→user-service→DB

**验收标准**：
```bash
# video-service能通过gRPC调用user-service
curl http://localhost:8083/api/v1/videos
# 应该返回实际数据，而不是空数组
```

#### Week 3-4: 迁移media-service
**目标**：统一media-service使用共享数据库。

**任务**：
1. 移除media-service的独立db_pool
2. 改为通过gRPC调用user-service
3. 数据迁移（如果有独立数据）
4. 更新所有API端点

**优先级说明**：
- media-service已经有实现 ✅
- 只需要改为使用gRPC客户端
- 相对简单，风险低

### 第2个月：迁移video逻辑

#### Week 5-6: 提取video处理
**目标**：将video handlers迁移到video-service。

**迁移内容**（7,634行）：
```rust
// 从user-service迁移到video-service
handlers/videos.rs                // HTTP处理
handlers/uploads.rs               // 上传逻辑
services/video_service.rs         // 业务逻辑
services/transcoding_optimizer.rs // 转码
services/ffmpeg_optimizer.rs      // FFmpeg
services/video_job_queue.rs       // 任务队列
```

**迁移策略**：
1. 保留user-service中的gRPC服务器（向后兼容）
2. 在video-service中实现本地处理
3. 逐步切换流量（通过feature flag）
4. 验证后删除user-service中的代码

#### Week 7-8: WebSocket迁移
**目标**：处理视频相关的实时功能。

**问题**：
- video本身可能没有WebSocket（如果有，迁移）
- 主要是streaming需要WebSocket

### 第3个月：迁移streaming和recommendation

#### Week 9-10: Streaming迁移
**目标**：迁移直播功能（最复杂）。

**迁移内容**（1,000+行）：
```rust
handlers/streams.rs
handlers/streams_ws.rs            // WebSocket聊天
services/streaming/
  - stream_service.rs
  - stream_analytics.rs
  - rtmp_webhook.rs
  - viewer_counter.rs
  - stream_chat_store.rs
```

**特殊挑战**：
- WebSocket连接管理（actix-ws）
- Redis pub/sub广播
- RTMP webhook集成
- 观众计数（实时）

**策略**：
1. WebSocket在streaming-service中重新实现
2. 保持Redis作为共享状态（短期）
3. RTMP webhook切换到新服务
4. 逐步迁移聊天历史

#### Week 11-12: Recommendation迁移
**目标**：迁移推荐算法。

**迁移内容**（1,000+行）：
```rust
handlers/feed.rs
handlers/discover.rs
services/recommendation_v2/
  - ranking_engine.rs
  - onnx_serving.rs
services/experiments/
  - experiment_service.rs
  - assignment.rs
services/deep_learning_inference.rs
```

**依赖**：
- ClickHouse（feed排序）
- ONNX模型（推理服务）
- Kafka（用户行为事件）

**策略**：
1. ClickHouse保持共享（复杂查询）
2. ONNX模型文件复制到recommendation-service
3. Kafka consumer在recommendation-service
4. A/B测试新旧算法

---

## 数据库策略

### 短期（第1-2个月）：共享数据库
```
所有服务 → user-service的PostgreSQL
```

**理由**：
- ✅ 零迁移成本
- ✅ 事务完整性
- ✅ 快速验证架构
- ❌ DB是单点

**实施**：
- 所有新服务通过gRPC调用user-service
- user-service是唯一的数据访问层

### 中期（第3个月）：读写分离
```
写：user-service
读：新服务可以直接读取（read replica）
```

**理由**：
- ✅ 减少user-service压力
- ✅ 查询性能提升
- ❌ 需要配置read replica

### 长期（第4-6个月）：数据库分离
```
每个服务有自己的数据库
通过Kafka CDC同步
```

**理由**：
- ✅ 真正的服务独立
- ✅ 可扩展性
- ❌ 实施复杂
- ❌ 最终一致性

**顺序**：
1. recommendation-service（依赖ClickHouse，已经分离）
2. streaming-service（状态存储在Redis）
3. video-service（最后，因为依赖最多）

---

## 优先级排序（基于依赖和风险）

### P0（第1个月）：基础设施修复
1. **启动user-service的gRPC服务器** - 阻塞所有其他工作
2. **实现servers.rs的业务逻辑** - 连接到现有handlers
3. **统一media-service架构** - 当前是异类

### P1（第2个月）：Video迁移
**理由选择video优先**：
- ✅ 代码量最大（7,634行），收益最高
- ✅ 依赖相对独立（主要是S3和FFmpeg）
- ✅ 没有复杂的实时状态
- ❌ 但是有job queue依赖（转码任务）

### P2（第3个月）：Streaming和Recommendation
**Streaming**：
- ❌ 有WebSocket复杂性
- ❌ 有RTMP外部集成
- ❌ 有实时状态（观众计数）
- ✅ 但是用户量可能较小

**Recommendation**：
- ✅ 算法独立
- ✅ ClickHouse已经分离
- ❌ 但是依赖多个数据源（posts, follows, likes）

**建议顺序**：Streaming → Recommendation
- Streaming更紧急（实时性要求）
- Recommendation可以逐步优化

---

## 关键技术决策

### 1. Job Queue处理
**问题**：video转码需要异步处理。

**选项**：
- A. 保留在user-service（通过gRPC提交job）
- B. 迁移到video-service（独立job queue）
- C. 使用Kafka作为任务队列

**建议**：短期A，长期B
```rust
// 短期：video-service通过gRPC提交转码任务
video_service → gRPC → user-service → job_queue

// 长期：video-service有自己的job queue
video_service → 自己的job_queue → FFmpeg worker
```

### 2. WebSocket处理
**问题**：streaming的WebSocket连接在哪里？

**选项**：
- A. 保留在user-service
- B. 迁移到streaming-service

**建议**：B（迁移）
```rust
// streaming-service实现WebSocket服务器
streaming-service → actix-ws → Redis pub/sub

// user-service删除streams_ws.rs
```

**理由**：
- WebSocket连接与streaming业务逻辑紧密相关
- 降低user-service的复杂度
- streaming-service可以独立扩展（WebSocket节点）

### 3. Redis使用
**问题**：多个服务需要Redis（缓存、限流、pub/sub）。

**选项**：
- A. 共享Redis实例
- B. 每个服务独立Redis

**建议**：短期A，长期考虑B
```
短期（第1-2个月）：
所有服务 → 同一个Redis → 不同namespace

长期（第3个月+）：
- streaming-service → 独立Redis（pub/sub）
- video-service → 独立Redis（缓存）
- user-service → 独立Redis（session）
```

### 4. Kafka使用
**问题**：事件驱动架构中的Kafka。

**当前状态**：
- user-service有EventProducer（发布事件）
- CDC Consumer（PostgreSQL → ClickHouse）
- Events Consumer（处理业务事件）

**建议**：
```
短期：
- 保留user-service作为事件生产者
- 新服务通过gRPC触发事件发布

长期：
- 每个服务独立发布事件到Kafka
- 共享事件schema（proto定义）
```

---

## 风险和缓解措施

### 风险1：user-service成为瓶颈
**症状**：所有请求都要经过user-service的gRPC。

**缓解**：
- 使用HTTP/2多路复用（gRPC内置）
- 连接池配置优化（pool_size: 4 → 16）
- 监控gRPC延迟和吞吐量
- 如果成为瓶颈，优先级提升数据库分离

### 风险2：数据一致性
**症状**：共享数据库下的并发写入。

**缓解**：
- 短期：所有写操作仍通过user-service gRPC
- 使用数据库事务（ACID保证）
- 长期：使用Kafka CDC同步

### 风险3：迁移期间的双倍维护
**症状**：同时维护user-service和新服务的代码。

**缓解**：
- 使用feature flags切换流量
- 优先完成一个服务的迁移再开始下一个
- 自动化测试覆盖（集成测试）

### 风险4：WebSocket连接丢失
**症状**：streaming迁移时聊天断开。

**缓解**：
- 客户端自动重连机制
- 服务端保留消息历史（Redis）
- 灰度发布（10% → 50% → 100%）

---

## 成功指标

### 第1个月结束：
- ✅ user-service的gRPC服务器运行在:50051-50053
- ✅ video-service能通过gRPC获取实际数据
- ✅ media-service统一架构
- ✅ 端到端测试通过

### 第2个月结束：
- ✅ video-service处理50%的视频流量
- ✅ 转码任务正常工作
- ✅ 响应时间无明显增加（< +50ms）
- ✅ 错误率无上升

### 第3个月结束：
- ✅ streaming-service处理100%的直播流量
- ✅ recommendation-service处理feed排序
- ✅ user-service代码减少60%（从51K到20K行）
- ✅ 每个服务可以独立部署

---

## 结论

### 当前最紧急的任务（本周）

1. **修复user-service的gRPC服务器启动**（P0）
   - 在main.rs中添加启动代码
   - 传递db_pool, redis_client等依赖

2. **实现servers.rs的业务逻辑**（P0）
   - 连接到现有的handlers
   - 至少实现video相关的方法

3. **端到端验证**（P0）
   - video-service → gRPC → user-service → PostgreSQL
   - 返回实际数据

### Linus式总结

**你的问题不是缺少设计，而是缺少实现**。

你已经：
- ✅ 定义了proto（好）
- ✅ 创建了服务结构（好）
- ✅ 有了gRPC代理策略（好）

但是：
- ❌ gRPC服务器没启动（阻塞）
- ❌ 业务逻辑没连接（阻塞）
- ❌ 架构不统一（混乱）

**接下来3天的工作**：
1. 让gRPC服务器跑起来
2. 连接现有业务逻辑
3. 验证端到端流程

**不要做的事情**：
- ❌ 不要现在设计数据库分离
- ❌ 不要现在优化性能
- ❌ 不要现在重构算法

**记住Linus的话**：
> "先让它工作，再让它正确，最后让它快。"

现在你处于"让它工作"的阶段，其他的都是过早优化。
