# Phase 3 Implementation Guide: 實時個性化 Feed 排序系統

**基于现有代码分析** | **与 Nova Backend 兼容** | **分阶段指导**

---

## 📋 目录

1. [整体现状](#整体现状)
2. [关键阻塞项](#关键阻塞项)
3. [分阶段实施计划](#分阶段实施计划)
4. [Phase 1 详细指南：基础设施](#phase-1-详细指南基础设施)
5. [代码集成点](#代码集成点)
6. [测试策略](#测试策略)
7. [部署清单](#部署清单)

---

## 整体现状

### ✅ 已有组件（60%）

```
✓ ClickHouse 客户端 + 连接池 (src/db/ch_client.rs)
✓ Redis 缓存系统 (src/cache/feed_cache.rs)
✓ Feed 排序服务 (src/services/feed_ranking.rs)
✓ Feed Handler API (src/handlers/feed.rs)
✓ 趋势 Job (src/jobs/trending_generator.rs)
✓ 建议用户 Job (src/jobs/suggested_users_generator.rs)
✓ Events Handler 基础 (src/handlers/events.rs)
✓ Kafka 生产者 (src/services/kafka/producer.rs)
✓ JWT 认证、速率限制、指标系统
```

### ❌ 关键缺失（40%）

```
✗ CDC 消费者服务（PostgreSQL → Kafka → ClickHouse）
✗ Events 消费者服务（Events → ClickHouse）
✗ 事件去重逻辑
✗ ClickHouse 物化视图
✗ Circuit Breaker 模式
✗ 实时缓存失效
✗ CDC 管道指标
```

---

## 关键阻塞项

### 🔴 P0 - CRITICAL（必须解决才能启动 Phase 3）

#### 1. CDC 消费者服务（3-5 天工作量）

**当前问题**：
```
PostgreSQL (posts/likes/follows)
  ↓ Debezium CDC (configured 在 infra/)
  ↓ Kafka topics: cdc.posts, cdc.likes, ...
  ✗ [NOBODY CONSUMES] ← 数据丢失！
  ↓ ClickHouse (empty)
```

**需要实现**：
- `src/services/cdc_consumer.rs` - 从 Kafka CDC topics 消费
- Offset 管理（确保不丢失）
- 数据验证和转换
- 错误重试和死信队列

**文件**：
```
src/
├── services/
│   ├── cdc/
│   │   ├── consumer.rs         (NEW - 200 LOC)
│   │   ├── offset_manager.rs   (NEW - 150 LOC)
│   │   └── models.rs           (NEW - 100 LOC)
│   └── kafka/
│       └── consumer.rs         (REFACTOR - exists but needs work)
└── db/
    └── cdc_repo.rs             (NEW - 200 LOC)
```

**关键依赖**：
- `rdkafka` (已在 Cargo.toml)
- `clickhouse` (已在 Cargo.toml)
- PostgreSQL + Debezium (基础设施)

---

#### 2. Events 消费者服务（2-3 天工作量）

**当前问题**：
```
POST /api/v1/events
  ↓ src/handlers/events.rs (already implemented)
  ↓ Kafka producer (already sends to "events" topic)
  ✗ [NOBODY CONSUMES] ← 事件丢失！
  ↓ ClickHouse events table (empty)
```

**需要实现**：
- `src/services/events_consumer.rs` - 从 Kafka "events" topic 消费
- 事件去重（使用 Redis/PostgreSQL）
- ClickHouse 插入
- 错误处理和重试

**文件**：
```
src/
├── services/
│   ├── events/
│   │   ├── consumer.rs         (NEW - 250 LOC)
│   │   ├── dedup.rs            (NEW - 150 LOC)
│   │   └── models.rs           (NEW - 100 LOC)
│   └── kafka/
│       └── consumer.rs         (CREATE/REFACTOR)
└── db/
    └── events_repo.rs          (NEW - 150 LOC)
```

---

### 🟡 P1 - HIGH（阻塞大部分 Phase 3 功能）

#### 3. ClickHouse 物化视图

**当前问题**：
```
Events 表有 10M+ 行（未来会更多）
查询时：没有预聚合 → 每次查询扫描全表 → 慢！
```

**需要实现**：
- `events` → `post_metrics_1h` (每小时聚合)
- `events` → `user_author_90d` (用户-作者 90 天亲和度)
- 物化视图自动维护聚合

**文件**：
```
infra/
└── clickhouse/
    ├── views/
    │   ├── mv_post_metrics_1h.sql      (NEW)
    │   ├── mv_user_author_90d.sql      (NEW)
    │   └── mv_post_metrics_daily.sql   (NEW)
    └── tables/
        ├── events.sql                   (UPDATE - add MV config)
        └── post_metrics_1h.sql          (UPDATE)
```

**影响**：
- 没有这些，Query 时间：3-5s (不符合 ≤800ms SLO)
- 有这些，Query 时间：200-300ms ✓

---

#### 4. Circuit Breaker 模式

**当前问题**：
```
如果 ClickHouse 故障 → 所有查询失败 → Feed 完全不可用
应该：自动回退到 PostgreSQL 时序流
```

**需要实现**：
- `src/middleware/circuit_breaker.rs` (NEW - 200 LOC)
- 修改 `src/services/feed_ranking.rs` 使用 Circuit Breaker

**文件**：
```
src/
├── middleware/
│   └── circuit_breaker.rs      (NEW - 200 LOC)
└── services/
    └── feed_ranking.rs         (REFACTOR - add CB logic)
```

---

## 分阶段实施计划

### 时间表

```
Week 1 (Mon-Fri): Phase 1 - Foundation
  ├─ Mon: CDC 消费者基础 + Offset 管理
  ├─ Tue: CDC 消费者完整 + 测试
  ├─ Wed: Events 消费者基础
  ├─ Thu: Events 消费者完整 + 去重
  └─ Fri: 集成测试 + 修复

Week 2 (Mon-Fri): Phase 2 - Core Features
  ├─ Mon: ClickHouse 物化视图
  ├─ Tue: Circuit Breaker 实现
  ├─ Wed: 实时缓存失效
  ├─ Thu: 指标收集 (15+ 新指标)
  └─ Fri: 端到端测试

Week 3 (Mon-Fri): Phase 3 - Optimization
  ├─ Mon-Tue: 性能优化 (query profiling, indexing)
  ├─ Wed-Thu: 压力测试 (1k RPS, event-to-visible ≤5s)
  └─ Fri: 文档 + 部署准备

总计：15 工作日 (2 人团队 7.5 天)
```

---

## Phase 1 详细指南：基础设施

### Step 1.1: CDC 消费者服务（3 天）

#### 目标
- 从 Kafka 消费 CDC 变更（posts, follows, comments, likes）
- 正确管理 Offset（不丢失数据）
- 将数据插入 ClickHouse CDC 表

#### 1.1.1 创建 CdcMessage 模型

**文件**: `src/services/cdc/models.rs`

```rust
use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CdcMessage {
    pub table: String,                    // "posts", "follows", etc.
    pub op: CdcOperation,                 // INSERT, UPDATE, DELETE
    pub ts_ms: i64,                       // timestamp in ms
    pub before: Option<serde_json::Value>,
    pub after: serde_json::Value,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
pub enum CdcOperation {
    #[serde(rename = "c")]
    Insert,
    #[serde(rename = "u")]
    Update,
    #[serde(rename = "d")]
    Delete,
    #[serde(rename = "r")]
    Read,
}

impl CdcMessage {
    pub fn validate(&self) -> Result<(), String> {
        // Validate required fields
        if self.table.is_empty() {
            return Err("table is required".to_string());
        }
        if self.after.is_null() {
            return Err("after is required".to_string());
        }
        Ok(())
    }
}
```

**检查点**:
- [ ] 编译通过（cargo check）
- [ ] 在 `src/services/mod.rs` 中 pub mod cdc

---

#### 1.1.2 创建 Offset 管理器

**文件**: `src/services/cdc/offset_manager.rs`

```rust
use std::sync::Arc;
use sqlx::PgPool;
use tracing::{info, error};
use crate::error::Result;

pub struct OffsetManager {
    db: Arc<PgPool>,
}

impl OffsetManager {
    pub fn new(db: Arc<PgPool>) -> Self {
        Self { db }
    }

    /// 创建 offset 表（如果不存在）
    pub async fn initialize(&self) -> Result<()> {
        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS cdc_offsets (
                topic TEXT NOT NULL,
                partition INT NOT NULL,
                "offset" BIGINT NOT NULL,
                updated_at TIMESTAMP DEFAULT NOW(),
                PRIMARY KEY (topic, partition)
            )
            "#
        )
        .execute(self.db.as_ref())
        .await?;
        Ok(())
    }

    /// 保存 offset
    pub async fn save_offset(&self, topic: &str, partition: i32, offset: i64) -> Result<()> {
        sqlx::query(
            r#"
            INSERT INTO cdc_offsets (topic, partition, "offset", updated_at)
            VALUES ($1, $2, $3, NOW())
            ON CONFLICT (topic, partition) DO UPDATE
            SET "offset" = $3, updated_at = NOW()
            "#
        )
        .bind(topic)
        .bind(partition)
        .bind(offset)
        .execute(self.db.as_ref())
        .await?;
        Ok(())
    }

    /// 读取最后保存的 offset
    pub async fn read_offset(&self, topic: &str, partition: i32) -> Result<Option<i64>> {
        let row = sqlx::query_scalar::<_, i64>(
            "SELECT \"offset\" FROM cdc_offsets WHERE topic = $1 AND partition = $2"
        )
        .bind(topic)
        .bind(partition)
        .fetch_optional(self.db.as_ref())
        .await?;
        Ok(row)
    }
}
```

**检查点**:
- [ ] 在数据库中创建 cdc_offsets 表
- [ ] 可以保存和读取 offset

---

#### 1.1.3 创建 CDC 消费者

**文件**: `src/services/cdc/consumer.rs` (主要实现)

```rust
use rdkafka::consumer::{Consumer, StreamConsumer};
use rdkafka::ClientConfig;
use std::sync::Arc;
use tracing::{info, error, warn, debug};
use sqlx::PgPool;
use crate::db::ClickHouseClient;
use crate::error::Result;
use super::{models::CdcMessage, offset_manager::OffsetManager};

pub struct CdcConsumer {
    kafka_consumer: Arc<StreamConsumer>,
    offset_manager: Arc<OffsetManager>,
    ch_client: Arc<ClickHouseClient>,
    db: Arc<PgPool>,
}

impl CdcConsumer {
    pub async fn new(
        brokers: &str,
        db: Arc<PgPool>,
        ch_client: Arc<ClickHouseClient>,
    ) -> Result<Self> {
        // Initialize offset manager
        let offset_mgr = Arc::new(OffsetManager::new(db.clone()));
        offset_mgr.initialize().await?;

        // Create Kafka consumer
        let consumer: StreamConsumer = ClientConfig::new()
            .set("bootstrap.servers", brokers)
            .set("group.id", "nova-cdc-consumer-v1")
            .set("auto.offset.reset", "earliest")
            .set("enable.auto.commit", "false")  // Manual commit
            .set("session.timeout.ms", "6000")
            .create()?;

        // Subscribe to CDC topics
        consumer.subscribe(&[
            "cdc.posts",
            "cdc.follows",
            "cdc.comments",
            "cdc.likes",
        ])?;

        Ok(Self {
            kafka_consumer: Arc::new(consumer),
            offset_manager: offset_mgr,
            ch_client,
            db,
        })
    }

    /// Start consuming CDC messages
    pub async fn run(&self) -> Result<()> {
        info!("Starting CDC consumer...");

        loop {
            match self.kafka_consumer.poll(std::time::Duration::from_secs(1)) {
                Some(Ok(msg)) => {
                    if let Err(e) = self.process_message(&msg).await {
                        error!("Failed to process CDC message: {}", e);
                        // Don't commit offset on error, will retry
                    } else {
                        // Successfully processed, commit offset
                        if let Err(e) = self.kafka_consumer.commit_message(&msg, false) {
                            warn!("Failed to commit offset: {}", e);
                        }
                    }
                },
                Some(Err(e)) => {
                    error!("Kafka error: {}", e);
                    tokio::time::sleep(std::time::Duration::from_secs(1)).await;
                },
                None => {
                    debug!("No message in poll interval");
                }
            }
        }
    }

    /// Process individual CDC message
    async fn process_message(&self, msg: &rdkafka::message::BorrowedMessage) -> Result<()> {
        let payload = msg.payload()
            .ok_or("Message has no payload")?;
        let payload_str = String::from_utf8(payload.to_vec())?;

        let cdc_msg: CdcMessage = serde_json::from_str(&payload_str)?;
        cdc_msg.validate()?;

        debug!("Processing CDC message: table={}, op={:?}", cdc_msg.table, cdc_msg.op);

        // Insert into ClickHouse
        match cdc_msg.table.as_str() {
            "posts" => self.insert_post_cdc(&cdc_msg).await?,
            "follows" => self.insert_follows_cdc(&cdc_msg).await?,
            "comments" => self.insert_comments_cdc(&cdc_msg).await?,
            "likes" => self.insert_likes_cdc(&cdc_msg).await?,
            _ => {
                warn!("Unknown CDC table: {}", cdc_msg.table);
            }
        }

        Ok(())
    }

    /// Insert posts CDC record
    async fn insert_post_cdc(&self, msg: &CdcMessage) -> Result<()> {
        // Extract fields from msg.after
        let query = r#"
            INSERT INTO posts_cdc (post_id, user_id, created_at, deleted, _version)
            VALUES
        "#;

        // TODO: Implement with proper field extraction
        // For now, use a helper method to extract values from JSON

        Ok(())
    }

    // ... Similar methods for follows, comments, likes
}
```

**检查点**:
- [ ] Kafka consumer 连接成功
- [ ] 可以读取 CDC messages
- [ ] Offset 管理工作正确

---

#### 1.1.4 在主服务中集成 CDC 消费者

**文件**: `src/main.rs` - 添加 Job 启动逻辑

```rust
// 在 main() 中添加：

// Start CDC consumer as background task
let db_clone = db_pool.clone();
let ch_clone = ch_client.clone();
let broker_config = config.kafka_brokers.clone();

tokio::spawn(async move {
    match services::cdc::consumer::CdcConsumer::new(
        &broker_config,
        Arc::new(db_clone),
        Arc::new(ch_clone),
    ).await {
        Ok(consumer) => {
            if let Err(e) = consumer.run().await {
                error!("CDC consumer error: {}", e);
            }
        }
        Err(e) => {
            error!("Failed to initialize CDC consumer: {}", e);
        }
    }
});

info!("CDC consumer started");
```

**检查点**:
- [ ] 服务器启动时 CDC consumer 也启动
- [ ] 日志显示 "CDC consumer started"

---

### Step 1.2: Events 消费者服务（2 天）

#### 目标
- 从 Kafka "events" topic 消费
- 实现去重（相同 event_id 不重复插入）
- 插入 ClickHouse events 表

#### 1.2.1 创建 Events 去重器

**文件**: `src/services/events/dedup.rs`

```rust
use std::sync::Arc;
use redis::aio::Connection;
use tracing::debug;
use crate::error::Result;

pub struct EventDeduplicator {
    redis_conn: Arc<tokio::sync::Mutex<Connection>>,
}

impl EventDeduplicator {
    pub fn new(redis_conn: Arc<tokio::sync::Mutex<Connection>>) -> Self {
        Self { redis_conn }
    }

    /// Check if event was already processed (within last 1 hour)
    pub async fn is_duplicate(&self, event_id: &str) -> Result<bool> {
        let key = format!("events:dedup:{}", event_id);
        let mut conn = self.redis_conn.lock().await;

        let exists: bool = redis::cmd("EXISTS")
            .arg(&key)
            .query_async(&mut *conn)
            .await?;

        Ok(exists)
    }

    /// Mark event as processed (TTL 1 hour)
    pub async fn mark_processed(&self, event_id: &str) -> Result<()> {
        let key = format!("events:dedup:{}", event_id);
        let mut conn = self.redis_conn.lock().await;

        redis::cmd("SETEX")
            .arg(&key)
            .arg(3600)  // 1 hour TTL
            .arg("1")
            .query_async(&mut *conn)
            .await?;

        Ok(())
    }
}
```

---

#### 1.2.2 创建 Events 消费者

**文件**: `src/services/events/consumer.rs`

```rust
use rdkafka::consumer::{Consumer, StreamConsumer};
use rdkafka::ClientConfig;
use std::sync::Arc;
use tracing::{info, error, debug};
use crate::db::ClickHouseClient;
use crate::error::Result;
use super::dedup::EventDeduplicator;

pub struct EventsConsumer {
    kafka_consumer: Arc<StreamConsumer>,
    ch_client: Arc<ClickHouseClient>,
    dedup: Arc<EventDeduplicator>,
}

impl EventsConsumer {
    pub async fn new(
        brokers: &str,
        ch_client: Arc<ClickHouseClient>,
        dedup: Arc<EventDeduplicator>,
    ) -> Result<Self> {
        let consumer: StreamConsumer = ClientConfig::new()
            .set("bootstrap.servers", brokers)
            .set("group.id", "nova-events-consumer-v1")
            .set("auto.offset.reset", "earliest")
            .set("enable.auto.commit", "true")  // Auto-commit OK for events (idempotent)
            .create()?;

        consumer.subscribe(&["events"])?;

        Ok(Self {
            kafka_consumer: Arc::new(consumer),
            ch_client,
            dedup,
        })
    }

    pub async fn run(&self) -> Result<()> {
        info!("Starting Events consumer...");

        loop {
            match self.kafka_consumer.poll(std::time::Duration::from_secs(1)) {
                Some(Ok(msg)) => {
                    if let Err(e) = self.process_message(&msg).await {
                        error!("Failed to process event: {}", e);
                    }
                },
                Some(Err(e)) => {
                    error!("Kafka error: {}", e);
                    tokio::time::sleep(std::time::Duration::from_secs(1)).await;
                },
                None => {
                    debug!("No message in poll interval");
                }
            }
        }
    }

    async fn process_message(&self, msg: &rdkafka::message::BorrowedMessage) -> Result<()> {
        let payload = msg.payload()
            .ok_or("Message has no payload")?;
        let payload_str = String::from_utf8(payload.to_vec())?;

        let event: serde_json::Value = serde_json::from_str(&payload_str)?;
        let event_id = event["event_id"].as_str()
            .ok_or("Missing event_id")?;

        // Deduplication
        if self.dedup.is_duplicate(event_id).await? {
            debug!("Skipping duplicate event: {}", event_id);
            return Ok(());
        }

        // Insert into ClickHouse
        self.ch_client.insert_event(&event).await?;

        // Mark as processed
        self.dedup.mark_processed(event_id).await?;

        Ok(())
    }
}
```

---

#### 1.2.3 更新 ClickHouseClient 以支持 insert_event

**文件**: `src/db/ch_client.rs` - 添加方法

```rust
impl ClickHouseClient {
    pub async fn insert_event(&self, event: &serde_json::Value) -> Result<()> {
        let query = r#"
            INSERT INTO events
            (event_id, event_time, user_id, post_id, author_id, action, dwell_ms, device, app_ver)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        "#;

        // Extract fields and insert
        // TODO: implement with proper error handling

        Ok(())
    }
}
```

---

### Step 1.3: 集成和测试

#### 1.3.1 创建集成测试

**文件**: `tests/integration/cdc_events_pipeline_test.rs`

```rust
#[tokio::test]
async fn test_full_cdc_events_pipeline() {
    // 1. Setup: Start Kafka, PostgreSQL, ClickHouse
    // 2. Insert record in PostgreSQL
    // 3. Wait for Debezium to publish to Kafka
    // 4. CDC consumer should consume and insert to CH
    // 5. Query ClickHouse to verify

    // Expected: Event visible in ClickHouse within 2 seconds
}
```

---

## 代码集成点

### 现有文件需要修改

#### 1. `src/main.rs`

```diff
+ // Start CDC consumer
+ tokio::spawn(async move { ... });
+
+ // Start Events consumer
+ tokio::spawn(async move { ... });
```

#### 2. `src/services/mod.rs`

```diff
+ pub mod cdc;
+ pub mod events;
```

#### 3. `Cargo.toml` (dependencies)

所有依赖已在 workspace dependencies 中：
- `rdkafka` ✓
- `clickhouse` ✓
- `sqlx` ✓
- `redis` ✓

---

## 测试策略

### 单元测试
- CdcMessage 验证
- EventDeduplicator Redis 操作
- Offset Manager 数据库操作

### 集成测试
- 完整的 CDC → CH 管道
- 完整的 Events → CH 管道
- 端到端延迟测试（<2s）

### 压力测试
- 1000 events/sec
- 1000 CDC changes/sec
- 验证去重有效性

---

## 部署清单

- [ ] PostgreSQL Debezium CDC 已配置
- [ ] Kafka 主题已创建 (cdc.*, events)
- [ ] ClickHouse 表已创建 (posts_cdc, follows_cdc, events, etc.)
- [ ] Redis 去重键空间已准备
- [ ] CDC consumer 代码完成
- [ ] Events consumer 代码完成
- [ ] 集成测试通过
- [ ] 压力测试通过 (1k RPS)
- [ ] 监控指标已配置
- [ ] 运维手册已准备

---

## 后续步骤（Phase 2）

完成 Phase 1 后：

1. **ClickHouse 物化视图** (2 天)
   - 创建 `post_metrics_1h` 聚合
   - 创建 `user_author_90d` 亲和度表

2. **Circuit Breaker** (1 天)
   - 添加到 Feed Ranking Service
   - 自动回退到 PostgreSQL

3. **实时缓存失效** (1 天)
   - 订阅 events，实时失效用户缓存
   - 取代基于 TTL 的方式

4. **指标收集** (2 天)
   - CDC lag、Events lag
   - 去重率、插入延迟
   - Prometheus exporters

---

## 常见问题

**Q: 为什么 CDC consumer 不在原有代码中？**
A: 原有代码侧重于 HTTP API 和 Redis 缓存。CDC 消费是流处理，需要单独的消费者线程/进程。

**Q: Events consumer 和 existing events handler 有什么区别？**
A:
- Events handler (`src/handlers/events.rs`): HTTP 端点，接收来自客户端的事件，写入 Kafka
- Events consumer (NEW): 从 Kafka 读取事件，写入 ClickHouse

**Q: 如何处理 Kafka 宕机？**
A:
- CDC consumer 会自动重试（rdkafka built-in）
- Events 暂时积压在 Kafka
- 恢复后自动继续消费

**Q: 去重是否会导致重复计算？**
A:
- Redis 去重是输入侧（不重复消费）
- ClickHouse 也有去重（相同 event_id 只保存一次）
- 两重保护确保正确性

---

## 支持资源

- Debezium 文档：https://debezium.io/documentation/
- rdkafka Rust：https://docs.rs/rdkafka/
- ClickHouse 客户端：https://docs.rs/clickhouse/

---

**下一步**: 确认是否从 Phase 1 开始实施？
