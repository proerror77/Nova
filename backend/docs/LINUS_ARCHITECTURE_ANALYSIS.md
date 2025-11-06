# Nova Backend - Linus 式架构分析与实现方法论

## 前言：为什么大多数实现会失败

在你开始分析这些服务的时候，请忘记我们列的那 520 小时估计。为什么？因为那是一个陷阱。

**问题不在于工作量，而在于错误的数据结构设计。**

---

## 第一原则：数据结构分析

> "Bad programmers worry about the code. Good programmers worry about data structures."

### 当前架构的致命问题

看看 Nova 系统的数据模型：

```
messaging-service      content-service       feed-service
  messages               posts                rankings
  conversations          comments             vectors
  reactions              reactions            cache_keys
  encryption_keys        likes                experiments
  device_tokens          video_assoc
```

**问题**: 这 7 个服务各自维护自己的"相似概念"（reactions, likes, follows），但：

1. **定义不统一** - 什么是 "engagement"？
   - messaging 中: 反应 (reaction)
   - content 中: 点赞 (likes) + 评论
   - feed 中: 排序分数 (engagement_score)

2. **查询模式分散** - 获取 "用户的所有互动":
   ```sql
   -- messaging 中:
   SELECT * FROM reactions WHERE user_id = ? AND conversation_id = ?
   
   -- content 中:
   SELECT * FROM likes WHERE user_id = ? AND post_id = ?
   
   -- feed 中:
   SELECT * FROM engagement_events WHERE user_id = ? AND post_id = ?
   ```
   
   三个不同的表，三种不同的查询。这是**数据结构设计失败**的标志。

3. **缓存策略冲突** - Redis 键命名:
   ```
   feed:user:{user_id}:cache          (TTL: 1小时)
   search:user:{user_id}:cache        (TTL: 30分钟)
   user:interactions:{user_id}        (TTL: 无限)
   notifications:unread:{user_id}     (TTL: 永久，手动失效)
   ```
   
   没有统一的缓存策略 = **隐藏的一致性bug**

### Linus 式解决方案：统一事件流

**不要建立 7 个独立的服务，而是建立一个统一的事件流。**

```
┌─────────────────────────────────────────────┐
│          Unified Event Stream (Kafka)        │
│                                              │
│  Topic: nova.user.events                     │
│  Topic: nova.content.events                  │
│  Topic: nova.engagement.events (新！)       │
│  Topic: nova.notification.events             │
└──────────────┬──────────────────────────────┘
               │
     ┌─────────┼─────────┬──────────┬──────────┐
     ▼         ▼         ▼          ▼          ▼
   PostgreSQL Outbox    Redis     ClickHouse  Vector DB
   (Primary)            (Cache)   (Analytics) (Search)
```

**为什么这个设计更好？**

1. **单一事实源** - 所有变化都通过事件流
2. **消费者独立** - 每个服务订阅自己关心的事件
3. **扩展性强** - 新服务只需订阅事件，无需改动现有代码
4. **调试容易** - 追踪 Kafka 日志就知道发生了什么

---

## 第二原则：消除特殊情况

> "有时你可以从不同角度看问题，重写它让特殊情况消失，变成正常情况。"

### 典例 1: Notification 服务的设计缺陷

**现在的设计** (坏):
```rust
pub struct CreateNotificationRequest {
    pub user_id: String,
    pub notification_type: String,  // "like", "comment", "follow"
    pub related_post_id: Option<String>,
    pub related_user_id: Option<String>,
    pub related_comment_id: Option<String>,
}

async fn create_notification(&self, req: CreateNotificationRequest) {
    match req.notification_type {
        "like" => {
            // INSERT with post_id
        }
        "comment" => {
            // INSERT with post_id AND comment_id
        }
        "follow" => {
            // INSERT with user_id only
        }
        _ => Err("unknown type")
    }
}
```

**问题**:
- 5 种通知类型 = 5 个特殊情况
- 每个分支都有不同的字段
- 添加新类型 = 修改 match 语句
- 测试需要覆盖所有分支

**Linus 式解决方案** (好):
```rust
pub struct NotificationEvent {
    pub user_id: String,
    pub event_type: String,
    pub entity_type: String,     // "post", "user", "comment"
    pub entity_id: String,       // UUID，统一格式
    pub actor_id: String,        // 谁触发的
    pub metadata: serde_json::Value,  // JSON，灵活扩展
    pub created_at: DateTime,
}

async fn process_event(&self, event: NotificationEvent) {
    // 单一代码路径！不需要 match
    let notification = Notification {
        user_id: event.user_id.clone(),
        event_id: event.event_type,
        entity_id: event.entity_id.clone(),
        actor_id: event.actor_id.clone(),
        metadata: event.metadata.clone(),
    };
    
    // 单个 INSERT
    db.insert_notification(&notification).await?;
    
    // 单个 Redis SET
    cache.set_unread_count(&event.user_id).await?;
}
```

**优势**:
- 代码路径只有 1 条（消除了 5 个特殊情况）
- 添加新通知类型：只需修改 `event_type` 生成器，不需要修改消费者
- 测试简化：1 个通用测试 + metadata 变体测试

### 典例 2: search-service 的多余层

**现在的设计** (坏):
```
User Request
    ↓
search-service (HTTP)
    ↓
search-service (gRPC internal logic)
    ↓
PostgreSQL FTS
    ↓
Redis cache
```

**问题**: 为什么要有搜索服务的 HTTP 层和 gRPC 实现？它们做的是同一件事！

**Linus 式解决方案** (好):
```
User Request (HTTP from frontend)
    ↓ (gateway routes to)
search-service gRPC endpoint
    ↓ (directly queries)
PostgreSQL FTS + Redis
```

**关键**：HTTP 和 gRPC 应该以**完全相同的方式**实现底层逻辑。如果你发现它们不同，说明设计有问题。

---

## 第三原则：不破坏任何东西

> "Never break userspace!"

在你实现任何新功能前，问自己：

**现有的依赖是什么？**

### messaging-service 的困境

```
现在: messaging-service 支持 WebSocket
计划: 迁移到 gRPC + Kafka events

风险: 所有 Web 客户端都连接到 WebSocket
     如果你关闭 WebSocket，所有用户断连！
```

**错误做法**:
1. 启用 gRPC
2. 关闭 WebSocket
3. 所有客户端都挂了 😱

**正确做法** (Linus 风格):
```
第一阶段: WebSocket + gRPC 并行运行
        消息同时写入两个队列
        
第二阶段: 监控 WebSocket 用户数
        等待降到可以接受的水平（比如 < 1%）
        
第三阶段: 向客户端推送升级
        给充足的缓冲时间（至少 1 个月）
        
第四阶段: 只有在 99% 的客户端升级后才关闭 WebSocket
```

**现实**: Nova 项目应该在每个服务的迁移计划中标记这一点。

---

## 第四原则：简洁执念

> "如果实现需要超过 3 层缩进，重新设计它"

### 问题代码示例

来自 `feed-service` 的推荐算法（模拟）:

```rust
pub async fn get_feed(&self, user_id: &str) -> Result<FeedResponse> {
    // Layer 1: Cache check
    if let Some(cached) = self.cache.get(user_id).await? {
        // Layer 2: Validation
        if self.validate_cache_age(&cached).await? {
            // Layer 3: Transform
            if let Some(posts) = &cached.posts {
                // Layer 4: Filter
                if posts.len() > 0 {
                    // Layer 5: Re-rank
                    return Ok(FeedResponse {
                        posts: self.rerank_posts(posts).await?,
                    });
                }
            }
        }
    }
    
    // ... 后面还有 6 层的 Kafka 消费逻辑
}
```

**问题**: 这是 7 层嵌套！代码变成了意大利面。

**Linus 式修复** - 使用 Early Return:

```rust
pub async fn get_feed(&self, user_id: &str) -> Result<FeedResponse> {
    // 检查缓存，有则直接返回
    if let Ok(cached) = self.cache.get(user_id).await {
        if self.is_cache_valid(&cached) && !cached.posts.is_empty() {
            return Ok(FeedResponse {
                posts: self.rerank_posts(&cached.posts).await?,
            });
        }
    }
    
    // 缓存未命中或无效，生成新 feed
    let posts = self.load_posts_from_db(user_id).await?;
    let ranked = self.rank_posts(user_id, &posts).await?;
    
    // 缓存结果
    self.cache.set(user_id, &ranked).await.ok();
    
    Ok(FeedResponse { posts: ranked })
}
```

**优势**:
- 最大缩进 2 层
- 每个分支清晰可读
- 新增需求只需新增一个 early return

---

## 实现优先级重新定义

基于以上分析，**真正的实现顺序应该是**：

### Phase 0: 架构修复 (不在 520 小时内)

**必须做的事** (这些不能跳):

1. **定义统一事件协议**
   - 所有跨服务通信都通过事件
   - 统一 UUID 格式、时间戳、元数据
   - 创建 `events.proto` 规范（已有骨架，需完善）

2. **建立 Outbox 模式**
   - PostgreSQL 中的 outbox 表
   - 每个写入操作都是事务性的
   - 一旦 INSERT，事件保证最终被 Kafka 发送

3. **实现通用错误处理**
   - 检查 `backend/libs/error-handling/`
   - 确保所有 RPC 方法使用统一错误码

**工作量**: 30-40 小时（通常被忽视，但价值最高）

### Phase 1: 事件基础设施 (Week 1-2)

**只实现两个关键服务**:

1. **events-service** ✅
   - 事件发布/订阅（Kafka）
   - Schema 验证
   - **不需要**数据库持久化（Kafka 就是存储）

2. **notification-service 消费者** ✅
   - 单一代码路径（如上所述）
   - Kafka → PostgreSQL → Redis → APNs
   - 如果需要改，改一个地方

**跳过**:
- search-service（搜索不是事件驱动）
- cdn-service（CDN 不是关键路径）
- streaming-service 的 HTTP 路由（后续再加）

### Phase 2: Feed 完成 (Week 3-4)

**关键insight**:
- Feed 依赖：content-service ✅ + search-service ✅ + user-service ✅
- 但搜索不需要"完整"实现，只需基本的 FTS

**实现顺序**:
1. search-service **最小实现** (30h, 不是 70h)
   - PostgreSQL FTS (GIN 索引)
   - Redis 缓存
   - **不需要**: 搜索建议、热搜（这些是优化，不是功能）

2. feed-service **完整实现** (60h, 不是 100h)
   - Redis 缓存（已有）
   - Kafka 消费 posts 事件
   - 简单排序算法（赞数 + 时间）
   - **延后**: ONNX 模型、Milvus、A/B 测试

**关键**: 先让功能跑起来，再优化算法。

### Phase 3: 完善与优化 (Week 5+)

一旦核心功能稳定：

1. 性能优化（缓存预热、索引调优）
2. ONNX 模型集成
3. A/B 测试框架
4. streaming-service 完整实现
5. cdn-service 完整实现

---

## 具体实现建议

### 1. Kafka Outbox 实现 (最关键)

**创建 PostgreSQL 表**:
```sql
CREATE TABLE outbox (
    id BIGSERIAL PRIMARY KEY,
    aggregate_id UUID NOT NULL,
    aggregate_type VARCHAR(255) NOT NULL,
    event_type VARCHAR(255) NOT NULL,
    payload JSONB NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    published_at TIMESTAMP,
    UNIQUE(aggregate_id, aggregate_type, event_type)
);
```

**应用端代码** (伪代码):
```rust
db.transaction(|tx| {
    // 原子操作：同时写入业务数据和事件
    tx.insert_post(&post).await?;
    tx.insert_outbox_event(Event {
        aggregate_id: post.id,
        aggregate_type: "Post",
        event_type: "PostCreated",
        payload: json!({ "post_id": post.id, "user_id": post.user_id }),
    }).await?;
    Ok(())
}).await?;
```

**Kafka 发送线程**:
```rust
loop {
    let events = db.get_unpublished_outbox_events(100).await?;
    for event in events {
        kafka.send(&event.event_type, &event.payload).await?;
        db.mark_as_published(&event.id).await?;
    }
    tokio::time::sleep(Duration::from_millis(100)).await;
}
```

**为什么这样设计**:
- ✅ 事件和数据同时提交，无竞态条件
- ✅ 即使 Kafka 宕机，事件会重试
- ✅ 消费者可以安全地假设事件是幂等的

### 2. unified error handling

所有 gRPC 方法应该遵循这个模式：

```rust
async fn some_rpc(&self, req: Request<Req>) -> Result<Response<Res>, Status> {
    let req = req.into_inner();
    
    // Early validation
    req.validate().map_err(|e| Status::invalid_argument(e))?;
    
    // Business logic
    let result = self.service.do_something(&req)
        .await
        .map_err(|e| e.to_grpc_status())?;
    
    Ok(Response::new(result))
}
```

关键：**不要在每个方法里写错误处理逻辑**。用统一的 `AppError::to_grpc_status()`。

### 3. 测试策略

**不要写** 520 个小时的集成测试。改用：

1. **单元测试** (30%)
   - 业务逻辑测试
   - 数据转换测试

2. **集成测试** (50%)
   - 每个服务的 CRUD
   - Kafka 消费者验证
   - 缓存失效验证

3. **E2E 测试** (20%)
   - 3-4 个关键用户旅程
   - 不需要 30+ 场景，那是测试的过度设计

---

## 最终实现计划 (现实版本)

| 阶段 | 工作 | 工时 | 原因 |
|------|------|------|------|
| 0 | 架构修复 + Outbox 实现 | 40h | 比实现 520h 代码更重要 |
| 1 | events-service + notification 消费者 | 80h | 基础，做一次做对 |
| 2 | search-service (最小化) | 30h | 只需 FTS，不需优化 |
| 3 | feed-service (基础排序) | 60h | 先功能后优化 |
| 4 | 性能优化 + ONNX | 80h | 根据指标驱动 |
| | **总计** | **290h** | **比 520h 少 56%** |

---

## 最后的话

你现在有两条路：

1. **按 520 小时的计划做** - 6 周内完成，但大概率过程中发现设计问题，最后花 800+ 小时。

2. **按 290 小时 + 架构修复做** - 4 周完成，后续可以自信地优化，因为基础打对了。

选择权在你。

但如果你问 Linus，他会说："如果你没有花至少 20% 的时间思考数据结构，你正在为之后的 bug 付利息。"

---

**版本**: 1.0
**风格**: Linus Torvalds 视角
**状态**: 需要团队讨论和决策
