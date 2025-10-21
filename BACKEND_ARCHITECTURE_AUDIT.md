# Backend Architecture Deep Audit
**Auditor**: Linus Torvalds (Backend System Architect)
**Date**: 2025-10-21
**Scope**: `/backend` directory architecture review
**Project**: Nova Social Platform

---

## 【架构评分】

**总分: 4/10** 🔴

这是个典型的"看起来像微服务,实际是个巨石"的架构。表面上有Kafka、Redis、ClickHouse这些分布式组件,但本质上只有**一个单体服务**(user-service)在扮演所有角色。这不是微服务架构,这是**带着分布式组件的单体架构**。

---

## 【关键问题】Top 5 致命架构问题

### 1. **伪微服务架构** 🔴 严重

**问题**: 所有功能塞在一个 `user-service` 里
- 123个Rust源文件全在一个服务里
- 54个handler函数处理从认证到消息到视频的所有业务
- 一个服务依赖8个基础设施组件(PostgreSQL, Redis, Kafka, ClickHouse, S3, Debezium, Zookeeper, WebSocket)

**为什么垃圾**:
```rust
// main.rs 的启动流程 - 一个服务做了太多事
let db_pool = create_pool(...);           // PostgreSQL
let redis_manager = redis_client.get_connection_manager(); // Redis
let clickhouse_client = ClickHouseClient::new(...);         // ClickHouse
let event_producer = EventProducer::new(...);               // Kafka Producer
let cdc_consumer = CdcConsumer::new(...);                   // CDC Consumer
let events_consumer = EventsConsumer::new(...);             // Events Consumer
let streaming_hub = StreamingHub::new().start();            // WebSocket Hub
let s3_client = s3_service::get_s3_client(...);            // S3

// 然后在main.rs里启动了4个后台任务:
tokio::spawn(cdc_consumer.run());         // CDC同步任务
tokio::spawn(events_consumer.run());      // Events处理任务
tokio::spawn(image_processor_worker);     // 图片处理任务
// + WebSocket Actor系统一直运行
```

**Bad Taste**: 一个服务的main函数有441行,初始化了8个外部系统。这是"好品味"的反面教材。

**应该怎么做**:
```
正确的微服务边界:
1. auth-service       - 只管认证/授权 (PostgreSQL, Redis, JWT)
2. social-service     - 社交图谱 (PostgreSQL, Redis)
3. content-service    - 内容管理 (PostgreSQL, S3)
4. feed-service       - 个性化推荐 (ClickHouse, Redis)
5. messaging-service  - 私信/E2E加密 (PostgreSQL, Redis, WebSocket)
6. notification-service - 通知推送 (Redis, Kafka Consumer)
7. cdc-worker         - CDC同步任务 (Kafka Consumer → ClickHouse)
8. events-worker      - 事件分析任务 (Kafka Consumer → ClickHouse)
```

每个服务应该:
- 只依赖1-2个数据存储
- 有明确的领域边界
- 通过Kafka/gRPC通信,不直接访问其他服务数据库

---

### 2. **数据流混乱** 🔴 严重

**问题**: 数据在多个系统间无序流动,没有清晰的"single source of truth"

**当前数据流**:
```
PostgreSQL (OLTP - 事务数据)
   ↓ (Debezium CDC)
Kafka (cdc.posts, cdc.follows, cdc.comments, cdc.likes)
   ↓ (CdcConsumer)
ClickHouse (OLAP - 分析数据)
   ↑
   | (另一条路径)
   |
Application Events → Kafka (events topic) → EventsConsumer → ClickHouse
```

**混乱点**:
1. **两条数据入ClickHouse的路径**: CDC同步 vs 应用事件,容易数据不一致
2. **Redis被当作万能缓存**: Feed缓存、Token黑名单、Email验证、Session、消息Pub/Sub全在Redis
3. **没有数据版本控制**: PostgreSQL和ClickHouse数据不一致时怎么办?
4. **缺少数据对账机制**: 如何验证PostgreSQL → ClickHouse的数据完整性?

**Bad Taste**: 你有两条路径写入同一个系统(ClickHouse),这本质上是个竞态条件。当CDC和Application Events都尝试更新同一个post的metrics时,谁赢?

**应该怎么做**:
```
清晰的数据流:
1. PostgreSQL是唯一的"真相源"(Write Path)
2. 所有变更通过Debezium CDC → Kafka
3. 所有下游消费者只从Kafka读取(统一Read Path)
4. Application不直接写Kafka,只写PostgreSQL
5. ClickHouse是只读副本,用于分析查询

数据层级:
PostgreSQL (L1 - Source of Truth)
   ↓
Kafka (L2 - Event Stream)
   ↓
ClickHouse (L3 - Analytics)
Redis (L4 - Cache)
```

---

### 3. **缺少API设计规范** 🟡 中等

**问题**: REST API设计不统一,缺少版本控制策略

**当前问题**:
```rust
// 路由定义散落在main.rs的380行代码里
web::scope("/api/v1")
    .route("/health", web::get().to(handlers::health_check))
    .service(web::scope("/feed").wrap(JwtAuthMiddleware)...)
    .service(web::scope("/events")...)
    .service(web::scope("/auth")...)
    .service(web::scope("/posts").wrap(JwtAuthMiddleware)...)
    .service(web::scope("/streams")...)
    .service(web::scope("").configure(handlers::messaging::configure_routes))
```

**坏味道**:
1. `/api/v1`硬编码,如何升级到v2?
2. 中间件(JwtAuthMiddleware)重复应用,应该有统一的认证层
3. `/streams/{stream_id}/ws` 混合了REST和WebSocket,路径不一致
4. `web::scope("")` 是什么鬼?空路径?
5. 缺少OpenAPI/Swagger文档自动生成

**应该怎么做**:
```rust
// 1. 版本化API Gateway
trait ApiVersion {
    fn configure_routes(cfg: &mut web::ServiceConfig);
}

struct ApiV1;
impl ApiVersion for ApiV1 {
    fn configure_routes(cfg: &mut web::ServiceConfig) {
        cfg.service(auth_routes())
           .service(feed_routes())
           .service(messaging_routes());
    }
}

// 2. 统一的认证策略
fn auth_routes() -> Scope {
    web::scope("/auth")
        .route("/login", web::post().to(login))
        .route("/register", web::post().to(register))
        .service(
            web::scope("/protected")
                .wrap(JwtAuthMiddleware) // 只包一次
                .route("/logout", web::post().to(logout))
                .route("/refresh", web::post().to(refresh))
        )
}

// 3. 自动生成OpenAPI文档
#[derive(OpenApi)]
#[openapi(paths(login, register, logout))]
struct ApiDoc;
```

---

### 4. **异步处理设计混乱** 🟡 中等

**问题**: 多种异步模式混用,缺少统一的错误处理和重试策略

**混乱的异步模式**:
```rust
// 模式1: MPSC Channel (job_queue)
let (job_sender, job_receiver) = job_queue::create_job_queue(100);
tokio::spawn(image_processor_worker);

// 模式2: Kafka Consumer (cdc_consumer)
tokio::spawn(async move { cdc_consumer.run().await });

// 模式3: Kafka Consumer (events_consumer)
tokio::spawn(async move { events_consumer.run().await });

// 模式4: Actix Actor System (streaming_hub)
let streaming_hub = StreamingHub::new().start();

// 模式5: Redis Pub/Sub (messaging WebSocket)
// 在websocket_handler.rs里隐藏
```

**问题**:
1. **5种不同的异步模式**,没有统一抽象
2. **错误处理不一致**: 有些panic,有些log,有些返回Result
3. **没有优雅关闭**: Kafka consumers用`abort()`,不是`graceful_shutdown()`
4. **缺少背压机制**: job_queue满了怎么办? Kafka消费太慢怎么办?
5. **没有重试策略**: CDC失败了重试几次?间隔多久?

**Bad Taste**: 你用了5种异步模式来做4种事情。这说明你不知道哪种模式适合哪种场景,所以全都试了一遍。

**应该怎么做**:
```rust
// 统一的异步任务抽象
#[async_trait]
trait BackgroundWorker {
    async fn run(&self) -> Result<(), WorkerError>;
    async fn graceful_shutdown(&self, timeout: Duration) -> Result<(), WorkerError>;
    fn health_check(&self) -> WorkerHealth;
}

// 统一的重试策略
struct RetryPolicy {
    max_attempts: u32,
    backoff: ExponentialBackoff,
    retry_on: Vec<ErrorKind>,
}

// 统一的错误处理
enum WorkerError {
    Transient(String),  // 可重试错误
    Fatal(String),      // 致命错误,停止worker
}

// 使用:
struct CdcWorker { ... }
impl BackgroundWorker for CdcWorker {
    async fn run(&self) -> Result<(), WorkerError> {
        loop {
            match self.process_message().await {
                Ok(_) => continue,
                Err(e) if e.is_transient() => {
                    self.retry_policy.retry(|| self.process_message()).await?
                }
                Err(e) => return Err(WorkerError::Fatal(e.to_string())),
            }
        }
    }
}
```

---

### 5. **依赖关系耦合严重** 🟡 中等

**问题**: 所有模块都依赖PgPool和Redis,形成了紧耦合

**当前依赖图**:
```
main.rs
 ├─► PgPool (被20+个模块依赖)
 ├─► ConnectionManager (Redis,被15+个模块依赖)
 ├─► ClickHouseClient (被5个模块依赖)
 ├─► EventProducer (被10个模块依赖)
 └─► Config (全局配置,被所有模块依赖)

handlers/
 ├─► auth.rs → 依赖: PgPool, Redis, Config
 ├─► posts.rs → 依赖: PgPool, Redis, S3Client, JobSender, Config
 ├─► feed.rs → 依赖: FeedRankingService → ClickHouseClient, Redis
 └─► messaging.rs → 依赖: PgPool, Redis, EventProducer, Config
```

**坏味道**:
1. **God Object**: PgPool和Redis被到处传递,是全局依赖
2. **循环依赖风险**: handlers调用services,services调用handlers(streaming_websocket)
3. **测试困难**: 每个handler测试都需要mock 4-5个依赖
4. **无法独立部署**: 所有模块强依赖同一个PostgreSQL和Redis

**应该怎么做**:
```rust
// 1. 依赖注入 + Trait抽象
#[async_trait]
trait UserRepository {
    async fn find_by_id(&self, id: Uuid) -> Result<User>;
    async fn create(&self, user: CreateUser) -> Result<User>;
}

struct PostgresUserRepo { pool: PgPool }
impl UserRepository for PostgresUserRepo { ... }

// 2. 分层架构
// handlers只依赖service,不直接依赖repository
async fn login(
    service: web::Data<dyn AuthService>,
    req: web::Json<LoginRequest>
) -> HttpResponse {
    service.login(req.into_inner()).await
}

// service层抽象所有数据访问
struct AuthServiceImpl {
    user_repo: Arc<dyn UserRepository>,
    token_service: Arc<dyn TokenService>,
    cache: Arc<dyn CacheService>,
}

// 3. 接口隔离
// 不要传递整个PgPool,只传需要的repository
struct FeedHandler {
    feed_service: Arc<dyn FeedService>, // 不直接依赖ClickHouse
}
```

---

## 【数据流分析】

### 当前数据流 (混乱)

```
┌─────────────────────────────────────────────────────────────┐
│ 用户请求 (HTTP/WebSocket)                                   │
└───────────────────────┬─────────────────────────────────────┘
                        ↓
        ┌───────────────────────────────┐
        │   user-service (单体)          │
        │  ┌─────────────────────────┐  │
        │  │ handlers (54 endpoints) │  │
        │  └────────┬────────────────┘  │
        │           ↓                    │
        │  ┌─────────────────────────┐  │
        │  │ services (37 modules)   │  │
        │  └─┬──┬──┬──┬──┬──┬──┬──┬─┘  │
        └────┼──┼──┼──┼──┼──┼──┼──┼────┘
             ↓  ↓  ↓  ↓  ↓  ↓  ↓  ↓
   ┌─────────┐ │  │  │  │  │  │  │
   │PostgreSQL│ │  │  │  │  │  │  │
   └────┬────┘ │  │  │  │  │  │  │
        │      │  │  │  │  │  │  │
   ┌────▼──────▼──┐  │  │  │  │  │
   │ Debezium CDC │  │  │  │  │  │
   └────┬─────────┘  │  │  │  │  │
        │            │  │  │  │  │  │
   ┌────▼────────────▼──┐  │  │  │  │
   │ Kafka (4 topics)   │◄─┘  │  │  │
   │ - cdc.*            │     │  │  │
   │ - events           │     │  │  │
   └────┬───────────────┘     │  │  │
        │                     │  │  │
   ┌────▼─────────────────────▼──┐  │
   │ ClickHouse               │  │
   │ (被2个consumer写入)       │  │
   └──────────────────────────┘  │
                                 │
   ┌──────────────────────────────▼──┐
   │ Redis (7种用途混在一起)          │
   │ 1. Session cache                │
   │ 2. Feed cache                   │
   │ 3. Token blacklist              │
   │ 4. Email verification           │
   │ 5. 2FA temp sessions            │
   │ 6. Event deduplication          │
   │ 7. Messaging pub/sub            │
   └─────────────────────────────────┘
        │
   ┌────▼────┐
   │ S3      │
   └─────────┘
```

**问题总结**:
1. **单点故障**: user-service挂了,所有功能全挂
2. **资源竞争**: 所有请求共享同一个PostgreSQL连接池(20个连接)
3. **无法独立扩展**: 想扩展Feed服务?必须扩展整个user-service
4. **数据一致性**: PostgreSQL → Kafka → ClickHouse链路上任何一环出问题,数据就不一致

---

### 理想数据流 (清晰)

```
┌─────────────────────────────────────────────────────────────┐
│ API Gateway (Kong/Envoy)                                     │
│ - 认证/授权                                                   │
│ - 路由分发                                                    │
│ - 限流/熔断                                                   │
└───┬───┬───┬────┬────┬─────┬─────┬─────┬──────────────────────┘
    │   │   │    │    │     │     │     │
    ↓   ↓   ↓    ↓    ↓     ↓     ↓     ↓
┌───────┐ ┌────────┐ ┌────────┐ ┌──────────┐
│ auth  │ │social  │ │content │ │  feed    │
│service│ │service │ │service │ │ service  │
└───┬───┘ └───┬────┘ └───┬────┘ └────┬─────┘
    │         │          │           │
    ↓         ↓          ↓           ↓
┌─────────────────────────────────────────┐
│ PostgreSQL (分库)                        │
│ - auth_db                               │
│ - social_db                             │
│ - content_db                            │
└────────────┬────────────────────────────┘
             ↓
      ┌─────────────┐
      │ Debezium    │
      └──────┬──────┘
             ↓
      ┌─────────────┐
      │ Kafka       │
      │ (统一事件流) │
      └──┬──┬───┬───┘
         │  │   │
         ↓  ↓   ↓
    ┌────────┐ ┌────────────┐
    │CDC     │ │events      │
    │worker  │ │worker      │
    └───┬────┘ └────┬───────┘
        └───────────▼────────┐
             ┌────────────┐  │
             │ClickHouse  │◄─┘
             │(只读副本)   │
             └────────────┘
```

**改进点**:
1. ✅ **服务独立**: 每个服务独立数据库,独立扩展
2. ✅ **职责明确**: auth只管认证,feed只管推荐
3. ✅ **数据单向流**: PostgreSQL → Kafka → ClickHouse,没有回路
4. ✅ **容错性强**: 任何一个服务挂了,其他服务继续工作

---

## 【耦合度分析】

### 模块耦合度评分

| 模块 | 依赖数量 | 被依赖数量 | 耦合度评分 | 级别 |
|------|---------|-----------|----------|------|
| main.rs | 14个基础设施组件 | 0 | 9/10 | 🔴 严重 |
| handlers/auth.rs | 5个(PgPool,Redis,Config,EmailService,JwtService) | 1个(main.rs) | 7/10 | 🔴 严重 |
| handlers/posts.rs | 6个(PgPool,Redis,S3,JobQueue,Config,EventProducer) | 1个(main.rs) | 8/10 | 🔴 严重 |
| handlers/feed.rs | 2个(FeedRankingService,Config) | 1个(main.rs) | 4/10 | 🟡 中等 |
| handlers/messaging.rs | 5个(PgPool,Redis,EventProducer,WebSocketHub,Config) | 1个(main.rs) | 7/10 | 🔴 严重 |
| services/feed_ranking.rs | 2个(ClickHouseClient,FeedCache) | 2个(handlers/feed,main.rs) | 5/10 | 🟡 中等 |
| services/cdc/consumer.rs | 3个(KafkaConsumer,ClickHouseClient,OffsetManager) | 1个(main.rs) | 6/10 | 🟡 中等 |
| services/events/consumer.rs | 3个(KafkaConsumer,ClickHouseClient,EventDeduplicator) | 1个(main.rs) | 6/10 | 🟡 中等 |

**问题**:
1. **main.rs是God Object**: 依赖14个外部系统,441行启动代码
2. **handlers高耦合**: 平均依赖5-6个基础设施组件
3. **没有依赖注入**: 所有依赖都是在main.rs里硬编码创建
4. **测试困难**: 测试一个handler需要mock 5-6个依赖

---

### 服务间依赖图 (当前只有1个服务)

```
user-service (单体)
 ├─► PostgreSQL (强依赖,无法降级)
 ├─► Redis (强依赖,无法降级)
 ├─► Kafka (强依赖,启动失败如果Kafka不可用)
 ├─► ClickHouse (弱依赖,有fallback到PostgreSQL)
 ├─► S3 (可选依赖,可以通过DISABLE_S3=true禁用)
 ├─► Debezium (间接依赖,通过Kafka)
 └─► Zookeeper (间接依赖,通过Kafka)

依赖层级:
L1 (必须): PostgreSQL, Redis
L2 (关键): Kafka, ClickHouse
L3 (可选): S3
L4 (基础设施): Zookeeper, Debezium
```

**问题**:
1. **单点故障**: PostgreSQL或Redis挂了,整个服务不可用
2. **启动依赖复杂**: 必须按顺序启动7个组件
3. **无法部分降级**: 不能只禁用某个功能,要么全开要么全关

---

## 【缓存策略分析】

### 当前缓存架构 🟡

**Redis用途清单**:
```rust
// 1. Feed缓存 (FeedCache)
key: feed:{user_id}:{algo}:{cursor}
ttl: 120s
value: Vec<PostId>

// 2. Session缓存 (未实现,应该有)
key: session:{access_token_hash}
ttl: 15min
value: UserId

// 3. Token黑名单 (token_revocation)
key: revoked:{access_token_hash}
ttl: 到token过期时间
value: "1"

// 4. Email验证Token (email_verification)
key: email_verify:{token}
ttl: 24h
value: {user_id, email}

// 5. 2FA临时Session (two_fa)
key: 2fa_session:{session_id}
ttl: 5min
value: {user_id, secret, backup_codes}

// 6. Event去重 (EventDeduplicator)
key: event_dedup:{event_id}
ttl: 3600s
value: "1"

// 7. Messaging Pub/Sub (websocket_handler)
channel: messaging:{user_id}
value: MessageEvent
```

**问题**:
1. **职责混乱**: Redis同时做缓存、会话存储、消息队列、去重
2. **无分库策略**: 7种用途混在同一个Redis实例的db0
3. **缓存命中率未知**: 没有监控feed cache的命中率
4. **无缓存预热**: Feed缓存cold start,第一次请求总是慢
5. **缺少CDN层**: 静态资源(图片)应该在CDN缓存,不应该走后端

---

### 理想缓存架构 ✅

```
┌────────────────────────────────────────────────────────┐
│ L1: CDN Cache (CloudFront/CloudFlare)                 │
│ - 图片/视频 (高命中率 95%)                              │
│ - TTL: 30天                                            │
└───────────────────┬────────────────────────────────────┘
                    ↓ (CDN Miss)
┌────────────────────────────────────────────────────────┐
│ L2: Application Cache (Redis Cluster - 3 instances)   │
│                                                        │
│ redis-session (db0):                                  │
│   - Session: key=session:{token}, ttl=15min          │
│   - Token黑名单: key=revoked:{token}, ttl=token_exp  │
│                                                        │
│ redis-feed (db1):                                     │
│   - Feed缓存: key=feed:{user_id}, ttl=120s          │
│   - 推荐缓存: key=discover:{category}, ttl=300s      │
│   - 预热机制: 每10分钟预热top 1000用户的feed          │
│                                                        │
│ redis-messaging (db2):                                │
│   - Pub/Sub: channel=msg:{user_id}                   │
│   - 在线状态: key=online:{user_id}, ttl=60s          │
└───────────────────┬────────────────────────────────────┘
                    ↓ (Cache Miss)
┌────────────────────────────────────────────────────────┐
│ L3: Database Query Result Cache (ClickHouse MergeTree)│
│ - 物化视图: feed_候选_mv (实时更新)                     │
│ - 预聚合: top_posts_1h, trending_24h                  │
└───────────────────┬────────────────────────────────────┘
                    ↓ (Analytical Query)
┌────────────────────────────────────────────────────────┐
│ L4: Source of Truth (PostgreSQL)                      │
│ - 原始数据,不缓存                                       │
└────────────────────────────────────────────────────────┘
```

**改进点**:
1. ✅ **分层缓存**: CDN → Redis → ClickHouse → PostgreSQL
2. ✅ **职责分离**: 3个Redis实例,各司其职
3. ✅ **缓存预热**: Feed缓存提前预热,减少cold start
4. ✅ **监控完善**: 每层缓存都有命中率监控

---

## 【数据库设计分析】

### Schema设计 🟢 基本合格

**优点**:
1. ✅ **规范化良好**: users, sessions, refresh_tokens分表
2. ✅ **索引齐全**: email, username, access_token_hash都有索引
3. ✅ **约束完整**: CHECK约束验证email格式、password长度
4. ✅ **软删除**: deleted_at字段,支持数据恢复
5. ✅ **时间戳**: created_at, updated_at自动维护

**问题**:
1. 🔴 **缺少分区**: posts表会无限增长,应该按created_at分区
2. 🟡 **无外键级联**: 删除user时,相关posts/sessions需要手动清理
3. 🟡 **缺少复合索引**: `(user_id, created_at)` 组合查询很常见,应该建复合索引

**推荐改进**:
```sql
-- 1. posts表分区 (按月)
CREATE TABLE posts (
    ...
) PARTITION BY RANGE (created_at);

CREATE TABLE posts_2025_01 PARTITION OF posts
    FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');

-- 2. 复合索引
CREATE INDEX idx_posts_user_created ON posts(user_id, created_at DESC);
CREATE INDEX idx_sessions_user_expires ON sessions(user_id, expires_at);

-- 3. 外键级联
ALTER TABLE sessions
    ADD CONSTRAINT fk_sessions_user
    FOREIGN KEY (user_id) REFERENCES users(id)
    ON DELETE CASCADE;
```

---

### 查询优化 🟡 中等

**好的模式**:
```rust
// 使用预编译语句
sqlx::query_as!(User,
    "SELECT * FROM users WHERE email = $1",
    email
).fetch_optional(pool).await
```

**坏的模式**:
```rust
// N+1查询问题 (在post_repo.rs)
for post in posts {
    let images = post_repo::get_images_by_post_id(pool, post.id).await?;
    let metadata = post_repo::get_metadata(pool, post.id).await?;
}

// 应该改成batch查询:
let post_ids: Vec<Uuid> = posts.iter().map(|p| p.id).collect();
let images = post_repo::get_images_by_post_ids(pool, &post_ids).await?;
let metadata = post_repo::get_metadata_batch(pool, &post_ids).await?;
```

---

## 【改进建议】

### 短期改进 (1-2周,不改变架构)

#### 1. 拆分main.rs 🔴 紧急
**当前**: 441行初始化代码,14个依赖
**目标**: <100行,只负责启动HTTP server

```rust
// 新的启动流程
#[actix_web::main]
async fn main() -> io::Result<()> {
    let config = Config::from_env()?;

    // 使用Builder模式初始化所有依赖
    let app_context = AppContextBuilder::new(config)
        .with_database()
        .with_redis()
        .with_kafka()
        .with_clickhouse()
        .with_s3()
        .build()
        .await?;

    // 启动所有后台任务
    let workers = WorkerManager::new()
        .spawn_cdc_worker(app_context.cdc_consumer)
        .spawn_events_worker(app_context.events_consumer)
        .spawn_image_worker(app_context.image_processor);

    // 启动HTTP server
    let server = HttpServerBuilder::new(app_context)
        .configure_routes()
        .bind(&config.bind_address())?
        .run();

    server.await?;
    workers.graceful_shutdown(Duration::from_secs(30)).await;
    Ok(())
}
```

**工作量**: 8小时

---

#### 2. 统一错误处理 🟡 重要
**当前**: 有些返回`Result`,有些panic,有些只log

```rust
// 统一的错误类型
#[derive(thiserror::Error, Debug)]
pub enum AppError {
    #[error("Database error: {0}")]
    Database(#[from] sqlx::Error),

    #[error("Redis error: {0}")]
    Redis(#[from] redis::RedisError),

    #[error("Kafka error: {0}")]
    Kafka(#[from] rdkafka::error::KafkaError),

    #[error("Validation error: {0}")]
    Validation(String),

    #[error("Not found: {0}")]
    NotFound(String),

    #[error("Unauthorized")]
    Unauthorized,
}

impl ResponseError for AppError {
    fn error_response(&self) -> HttpResponse {
        match self {
            AppError::Validation(msg) => {
                HttpResponse::BadRequest().json(ErrorResponse {
                    error: "validation_error",
                    message: msg,
                })
            }
            AppError::NotFound(msg) => {
                HttpResponse::NotFound().json(ErrorResponse {
                    error: "not_found",
                    message: msg,
                })
            }
            AppError::Unauthorized => {
                HttpResponse::Unauthorized().json(ErrorResponse {
                    error: "unauthorized",
                    message: "Invalid or expired token",
                })
            }
            _ => {
                tracing::error!("Internal error: {:?}", self);
                HttpResponse::InternalServerError().json(ErrorResponse {
                    error: "internal_error",
                    message: "An unexpected error occurred",
                })
            }
        }
    }
}
```

**工作量**: 12小时

---

#### 3. 添加OpenAPI文档 🟡 重要

```rust
// 使用utoipa自动生成OpenAPI文档
use utoipa::{OpenApi, ToSchema};

#[derive(OpenApi)]
#[openapi(
    paths(
        handlers::auth::register,
        handlers::auth::login,
        handlers::auth::logout,
    ),
    components(
        schemas(RegisterRequest, RegisterResponse, LoginRequest, AuthResponse)
    ),
    tags(
        (name = "auth", description = "Authentication endpoints")
    )
)]
struct ApiDoc;

// 在main.rs添加路由
.route("/api-doc/openapi.json", web::get().to(|| async {
    HttpResponse::Ok().json(ApiDoc::openapi())
}))
.route("/swagger-ui", web::get().to(swagger_ui))
```

**工作量**: 16小时 (需要为所有endpoints添加注解)

---

#### 4. 实现健康检查 🟢 简单

```rust
// 深度健康检查
#[get("/health/ready")]
async fn readiness_check(
    pool: web::Data<PgPool>,
    redis: web::Data<ConnectionManager>,
    clickhouse: web::Data<ClickHouseClient>,
) -> HttpResponse {
    let mut checks = vec![];

    // PostgreSQL
    let pg_ok = sqlx::query("SELECT 1").fetch_one(pool.get_ref()).await.is_ok();
    checks.push(("postgres", pg_ok));

    // Redis
    let redis_ok = redis::cmd("PING").query_async::<_, String>(redis.get_ref()).await.is_ok();
    checks.push(("redis", redis_ok));

    // ClickHouse
    let ch_ok = clickhouse.health_check().await.is_ok();
    checks.push(("clickhouse", ch_ok));

    let all_ok = checks.iter().all(|(_, ok)| *ok);

    if all_ok {
        HttpResponse::Ok().json(json!({
            "status": "healthy",
            "checks": checks,
        }))
    } else {
        HttpResponse::ServiceUnavailable().json(json!({
            "status": "unhealthy",
            "checks": checks,
        }))
    }
}
```

**工作量**: 4小时

---

### 中期改进 (1-2个月,小规模重构)

#### 1. 引入API Gateway 🔴 紧急

**目标**: 统一入口,认证/限流/路由分发

```yaml
# Kong配置示例
services:
  - name: auth-service
    url: http://user-service:8080
    routes:
      - paths: ["/api/v1/auth"]
        plugins:
          - name: rate-limiting
            config:
              minute: 100
              policy: local
          - name: cors
          - name: request-transformer
            config:
              add:
                headers: ["X-Service:auth"]

  - name: feed-service
    url: http://user-service:8080
    routes:
      - paths: ["/api/v1/feed"]
        plugins:
          - name: jwt
            config:
              uri_param_names: [jwt]
          - name: rate-limiting
            config:
              minute: 300
```

**工作量**: 32小时 (部署Kong + 配置所有路由)

---

#### 2. 拆分数据库 🟡 重要

**目标**: 按领域拆分PostgreSQL数据库

```
当前: nova_auth (单库)
 ├─ users
 ├─ sessions
 ├─ posts
 ├─ follows
 ├─ comments
 └─ messages

拆分后:
auth_db:
 ├─ users
 ├─ sessions
 └─ refresh_tokens

social_db:
 ├─ follows
 ├─ blocks
 └─ user_profiles

content_db:
 ├─ posts
 ├─ comments
 ├─ likes
 └─ post_images

messaging_db:
 ├─ messages
 ├─ message_keys
 └─ message_delivery
```

**工作量**: 80小时 (包括数据迁移脚本)

---

#### 3. 实现分布式追踪 🟡 重要

```rust
// 使用OpenTelemetry
use opentelemetry::{global, sdk::propagation::TraceContextPropagator};
use tracing_subscriber::layer::SubscriberExt;

#[actix_web::main]
async fn main() -> io::Result<()> {
    // 初始化Jaeger tracer
    global::set_text_map_propagator(TraceContextPropagator::new());

    let tracer = opentelemetry_jaeger::new_pipeline()
        .with_service_name("user-service")
        .install_simple()
        .expect("Failed to install Jaeger tracer");

    let telemetry = tracing_opentelemetry::layer().with_tracer(tracer);

    tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::new("info"))
        .with(tracing_subscriber::fmt::layer())
        .with(telemetry)
        .init();

    // ... 启动服务
}

// 在handler里自动追踪
#[tracing::instrument(skip(pool, redis))]
async fn login(
    pool: web::Data<PgPool>,
    redis: web::Data<ConnectionManager>,
    req: web::Json<LoginRequest>,
) -> Result<HttpResponse, AppError> {
    // 所有数据库查询、Redis操作都会自动追踪
    let user = user_repo::find_by_email(pool.get_ref(), &req.email).await?;
    // ...
}
```

**工作量**: 24小时

---

### 长期改进 (3-6个月,架构重构)

#### 1. 微服务拆分 🔴 核心

**拆分策略**:
```
Phase 1 (Month 1-2): 垂直拆分
 └─ 拆分出 auth-service (认证独立)
    工作量: 120小时

Phase 2 (Month 3-4): 水平拆分
 ├─ 拆分出 content-service (帖子/评论)
 └─ 拆分出 social-service (关注/屏蔽)
    工作量: 200小时

Phase 3 (Month 5-6): 专用服务
 ├─ 拆分出 feed-service (推荐算法)
 ├─ 拆分出 messaging-service (私信)
 └─ 拆分出 notification-service (通知)
    工作量: 240小时
```

**总工作量**: 560小时 (14周 × 40小时)

---

#### 2. Event Sourcing + CQRS 🟡 可选

**目标**: 用事件溯源替代直接修改数据库

```rust
// Event Store
pub enum UserEvent {
    UserRegistered { id: Uuid, email: String, username: String },
    EmailVerified { id: Uuid },
    PasswordChanged { id: Uuid },
    UserDeleted { id: Uuid },
}

// Command Handler (写入)
async fn register_user(cmd: RegisterUserCommand) -> Result<UserEvent> {
    // 1. 验证
    validate_email(&cmd.email)?;

    // 2. 生成事件
    let event = UserEvent::UserRegistered {
        id: Uuid::new_v4(),
        email: cmd.email,
        username: cmd.username,
    };

    // 3. 持久化事件到Event Store
    event_store.append("user-stream", event.clone()).await?;

    // 4. 发布事件到Kafka
    kafka_producer.send("user-events", event).await?;

    Ok(event)
}

// Query Handler (读取)
async fn get_user(id: Uuid) -> Result<User> {
    // 从Read Model读取 (PostgreSQL物化视图 或 ClickHouse)
    read_db.query("SELECT * FROM users_view WHERE id = $1", id).await
}

// Projector (更新Read Model)
async fn project_user_events(event: UserEvent) {
    match event {
        UserEvent::UserRegistered { id, email, username } => {
            sqlx::query!("INSERT INTO users_view (id, email, username) VALUES ($1, $2, $3)",
                id, email, username)
                .execute(pool).await?;
        }
        UserEvent::EmailVerified { id } => {
            sqlx::query!("UPDATE users_view SET email_verified = true WHERE id = $1", id)
                .execute(pool).await?;
        }
        // ...
    }
}
```

**优点**:
1. ✅ 完整的审计日志 (所有变更都有事件记录)
2. ✅ 时间旅行 (可以重放事件到任意时间点)
3. ✅ 读写分离 (写入Event Store,读取Read Model)

**缺点**:
1. ❌ 复杂度高 (需要维护Event Store + Read Model)
2. ❌ 最终一致性 (Read Model不是实时的)

**工作量**: 320小时 (仅建议核心业务使用,如订单/支付)

---

#### 3. gRPC服务间通信 🟢 推荐

**目标**: 用gRPC替代HTTP REST做服务间调用

```protobuf
// auth.proto
service AuthService {
    rpc ValidateToken (ValidateTokenRequest) returns (ValidateTokenResponse);
    rpc GetUserById (GetUserByIdRequest) returns (User);
}

message ValidateTokenRequest {
    string access_token = 1;
}

message ValidateTokenResponse {
    bool valid = 1;
    string user_id = 2;
    repeated string scopes = 3;
}
```

```rust
// gRPC服务端 (auth-service)
use tonic::{transport::Server, Request, Response, Status};

pub struct AuthServiceImpl {
    jwt_service: Arc<JwtService>,
}

#[tonic::async_trait]
impl AuthService for AuthServiceImpl {
    async fn validate_token(
        &self,
        request: Request<ValidateTokenRequest>,
    ) -> Result<Response<ValidateTokenResponse>, Status> {
        let token = request.into_inner().access_token;

        match self.jwt_service.validate(&token).await {
            Ok(claims) => Ok(Response::new(ValidateTokenResponse {
                valid: true,
                user_id: claims.sub,
                scopes: claims.scopes,
            })),
            Err(_) => Ok(Response::new(ValidateTokenResponse {
                valid: false,
                user_id: String::new(),
                scopes: vec![],
            })),
        }
    }
}

// gRPC客户端 (其他服务调用auth-service)
let mut client = AuthServiceClient::connect("http://auth-service:50051").await?;
let response = client.validate_token(ValidateTokenRequest {
    access_token: token.to_string(),
}).await?;

if !response.into_inner().valid {
    return Err(AppError::Unauthorized);
}
```

**优点**:
1. ✅ 性能更好 (HTTP/2, Protobuf二进制编码)
2. ✅ 强类型 (编译期类型检查)
3. ✅ 双向流 (支持streaming)

**工作量**: 160小时 (为所有服务间调用添加gRPC)

---

## 【总结】

### 核心问题根源

这个架构的本质问题是: **用单体架构实现了分布式系统的复杂度,但没有获得分布式系统的好处**。

你有Kafka、Redis、ClickHouse这些分布式组件,但所有逻辑都在一个`user-service`里。这意味着:
- ❌ 无法独立扩展任何功能
- ❌ 无法独立部署任何功能
- ❌ 单点故障风险极高
- ❌ 开发效率低 (所有人修改同一个代码库)

---

### 优先级建议

**P0 (立即修复,1-2周)**:
1. 拆分main.rs - 使用Builder模式
2. 统一错误处理 - 实现AppError
3. 添加健康检查 - 深度依赖检查
4. 添加OpenAPI文档 - 自动生成

**P1 (短期改进,1-2个月)**:
1. 引入API Gateway (Kong/Envoy)
2. 拆分Redis实例 (按用途分3个db)
3. 实现分布式追踪 (OpenTelemetry + Jaeger)
4. 优化N+1查询 (batch查询)

**P2 (中期重构,3-6个月)**:
1. 微服务拆分 (auth → content → social → feed)
2. 数据库分库 (按领域拆分)
3. gRPC服务间通信
4. Event Sourcing (可选,仅核心业务)

---

### 最后的建议

**如果这是生产环境代码,我会直接说: "这代码不能上线。"**

但如果这是MVP阶段,想快速验证产品,那么当前架构**勉强可以接受**,但必须:
1. 明确这是**临时架构**,6个月内必须重构
2. 限制用户规模 (<10K DAU)
3. 准备好随时降级的预案 (ClickHouse挂了怎么办?Kafka挂了怎么办?)

**"Bad code isn't the problem. The problem is not knowing it's bad code."**

现在你知道了。去修复它。

---

## 【附录】参考资源

1. **微服务模式**: https://microservices.io/patterns/
2. **CQRS模式**: https://martinfowler.com/bliki/CQRS.html
3. **Event Sourcing**: https://martinfowler.com/eaaDev/EventSourcing.html
4. **gRPC最佳实践**: https://grpc.io/docs/guides/
5. **Actix-web性能优化**: https://actix.rs/docs/

---

**End of Audit Report**
