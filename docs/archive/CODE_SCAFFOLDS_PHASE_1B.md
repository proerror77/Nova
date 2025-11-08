# Phase 1B 代码框架和实现模板

**本文档**: 即插即用的代码骨架
**目标**: 加速开发 (复制 → 修改 → 测试)
**语言**: Rust (所有代码)

---

## 📦 Task 1.1: Outbox 模式库

### 文件: backend/libs/event-schema/src/outbox.rs

```rust
//! 统一的 Outbox 事件模型和操作

use uuid::Uuid;
use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};
use sqlx::FromRow;

/// 统一的 Outbox 事件结构
#[derive(Debug, Clone, FromRow, Serialize, Deserialize)]
pub struct OutboxEvent {
    /// 事件唯一 ID
    pub id: Uuid,

    /// 业务对象 ID (message_id, post_id, user_id, etc)
    pub aggregate_id: Uuid,

    /// 事件类型 (MessageCreated, PostLiked, FollowAdded, etc)
    pub event_type: String,

    /// 事件负载 (JSON 格式)
    pub payload: serde_json::Value,

    /// 事件优先级 (0=Critical, 3=Low)
    pub priority: i32,

    /// 创建时间戳
    pub created_at: DateTime<Utc>,

    /// 发布到 Kafka 的时间戳 (NULL = 未发布)
    pub published_at: Option<DateTime<Utc>>,

    /// 重试次数
    pub retry_count: i32,

    /// 最后一次错误信息
    pub last_error: Option<String>,
}

impl OutboxEvent {
    /// 创建新的待发布事件
    pub fn new(
        aggregate_id: Uuid,
        event_type: impl Into<String>,
        payload: serde_json::Value,
        priority: i32,
    ) -> Self {
        Self {
            id: Uuid::new_v4(),
            aggregate_id,
            event_type: event_type.into(),
            payload,
            priority,
            created_at: Utc::now(),
            published_at: None,
            retry_count: 0,
            last_error: None,
        }
    }

    /// 生成 Kafka topic 名称
    pub fn kafka_topic(&self) -> String {
        format!("nova_events_{}", self.event_type.to_lowercase())
    }

    /// 生成 Kafka partition key (确保顺序)
    pub fn partition_key(&self) -> String {
        self.aggregate_id.to_string()
    }

    /// 转换为 Kafka 消息
    pub fn to_kafka_message(&self) -> Result<Vec<u8>, serde_json::Error> {
        serde_json::to_vec(self)
    }
}

/// 事件优先级定义
pub mod priority {
    pub const CRITICAL: i32 = 0;  // < 100ms 处理 (直播开始、安全事件)
    pub const HIGH: i32 = 1;      // < 1s 处理 (消息、评论)
    pub const NORMAL: i32 = 2;    // < 5s 处理 (赞、关注)
    pub const LOW: i32 = 3;       // < 1min 处理 (分析、清理)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_create_outbox_event() {
        let aggregate_id = Uuid::new_v4();
        let payload = serde_json::json!({ "sender_id": "123" });
        let event = OutboxEvent::new(
            aggregate_id,
            "MessageCreated",
            payload,
            priority::HIGH,
        );

        assert_eq!(event.event_type, "MessageCreated");
        assert_eq!(event.priority, 1);
        assert_eq!(event.kafka_topic(), "nova_events_messagecreated");
        assert_eq!(event.partition_key(), aggregate_id.to_string());
    }
}
```

### 文件: backend/libs/event-schema/src/lib.rs

```rust
//! Event schema library - 所有服务共用的事件定义

pub mod outbox;
pub mod events;

pub use outbox::{OutboxEvent, priority};
pub use events::DomainEvent;
```

### 文件: backend/libs/event-schema/src/events.rs

```rust
//! 领域事件定义 (业务驱动)

use uuid::Uuid;
use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};

/// 所有领域事件的枚举
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "event_type", content = "data")]
pub enum DomainEvent {
    // ===== Messaging Events =====
    MessageCreated {
        message_id: Uuid,
        sender_id: Uuid,
        recipient_id: Uuid,
        conversation_id: Uuid,
        content: String,
        created_at: DateTime<Utc>,
    },

    MessageEdited {
        message_id: Uuid,
        editor_id: Uuid,
        new_content: String,
        edited_at: DateTime<Utc>,
    },

    MessageDeleted {
        message_id: Uuid,
        deleter_id: Uuid,
        deleted_at: DateTime<Utc>,
    },

    // ===== Reaction Events =====
    ReactionAdded {
        reaction_id: Uuid,
        target_id: Uuid,  // message_id / post_id / comment_id
        target_type: String,  // "message" / "post" / "comment"
        user_id: Uuid,
        emoji: String,
        created_at: DateTime<Utc>,
    },

    ReactionRemoved {
        target_id: Uuid,
        target_type: String,
        user_id: Uuid,
        emoji: String,
        removed_at: DateTime<Utc>,
    },

    // ===== Follow Events =====
    FollowAdded {
        follower_id: Uuid,
        followee_id: Uuid,
        created_at: DateTime<Utc>,
    },

    FollowRemoved {
        follower_id: Uuid,
        followee_id: Uuid,
        removed_at: DateTime<Utc>,
    },

    // ===== Content Events =====
    PostCreated {
        post_id: Uuid,
        author_id: Uuid,
        title: String,
        content: String,
        tags: Vec<String>,
        created_at: DateTime<Utc>,
    },

    PostUpdated {
        post_id: Uuid,
        editor_id: Uuid,
        title: String,
        content: String,
        tags: Vec<String>,
        updated_at: DateTime<Utc>,
    },

    PostDeleted {
        post_id: Uuid,
        deleter_id: Uuid,
        deleted_at: DateTime<Utc>,
    },

    // ===== Notification Events (发布给用户) =====
    NotificationCreated {
        notification_id: Uuid,
        user_id: Uuid,
        title: String,
        body: String,
        notification_type: String,  // "mention" / "follow" / "like" / etc
        data: serde_json::Value,
        created_at: DateTime<Utc>,
    },

    // ===== Search Index Events =====
    SearchIndexUpdated {
        document_id: Uuid,
        document_type: String,  // "post" / "user" / "comment"
        operation: String,  // "index" / "update" / "delete"
        updated_at: DateTime<Utc>,
    },

    // ===== Streaming Events =====
    StreamStarted {
        stream_id: Uuid,
        broadcaster_id: Uuid,
        title: String,
        started_at: DateTime<Utc>,
    },

    StreamEnded {
        stream_id: Uuid,
        broadcaster_id: Uuid,
        ended_at: DateTime<Utc>,
    },

    StreamMessagePosted {
        stream_id: Uuid,
        sender_id: Uuid,
        message: String,
        posted_at: DateTime<Utc>,
    },
}

impl DomainEvent {
    /// 获取聚合根 ID (用作 Kafka partition key)
    pub fn aggregate_id(&self) -> Uuid {
        match self {
            DomainEvent::MessageCreated { message_id, .. } => *message_id,
            DomainEvent::MessageEdited { message_id, .. } => *message_id,
            DomainEvent::MessageDeleted { message_id, .. } => *message_id,
            DomainEvent::ReactionAdded { target_id, .. } => *target_id,
            DomainEvent::ReactionRemoved { target_id, .. } => *target_id,
            DomainEvent::FollowAdded { follower_id, .. } => *follower_id,
            DomainEvent::FollowRemoved { follower_id, .. } => *follower_id,
            DomainEvent::PostCreated { post_id, .. } => *post_id,
            DomainEvent::PostUpdated { post_id, .. } => *post_id,
            DomainEvent::PostDeleted { post_id, .. } => *post_id,
            DomainEvent::NotificationCreated { notification_id, .. } => *notification_id,
            DomainEvent::SearchIndexUpdated { document_id, .. } => *document_id,
            DomainEvent::StreamStarted { stream_id, .. } => *stream_id,
            DomainEvent::StreamEnded { stream_id, .. } => *stream_id,
            DomainEvent::StreamMessagePosted { stream_id, .. } => *stream_id,
        }
    }

    /// 获取事件类型字符串
    pub fn event_type(&self) -> String {
        match self {
            DomainEvent::MessageCreated { .. } => "MessageCreated".to_string(),
            DomainEvent::MessageEdited { .. } => "MessageEdited".to_string(),
            DomainEvent::MessageDeleted { .. } => "MessageDeleted".to_string(),
            DomainEvent::ReactionAdded { .. } => "ReactionAdded".to_string(),
            DomainEvent::ReactionRemoved { .. } => "ReactionRemoved".to_string(),
            DomainEvent::FollowAdded { .. } => "FollowAdded".to_string(),
            DomainEvent::FollowRemoved { .. } => "FollowRemoved".to_string(),
            DomainEvent::PostCreated { .. } => "PostCreated".to_string(),
            DomainEvent::PostUpdated { .. } => "PostUpdated".to_string(),
            DomainEvent::PostDeleted { .. } => "PostDeleted".to_string(),
            DomainEvent::NotificationCreated { .. } => "NotificationCreated".to_string(),
            DomainEvent::SearchIndexUpdated { .. } => "SearchIndexUpdated".to_string(),
            DomainEvent::StreamStarted { .. } => "StreamStarted".to_string(),
            DomainEvent::StreamEnded { .. } => "StreamEnded".to_string(),
            DomainEvent::StreamMessagePosted { .. } => "StreamMessagePosted".to_string(),
        }
    }

    /// 获取事件优先级
    pub fn priority(&self) -> i32 {
        use crate::priority::*;

        match self {
            // Critical (P0): 系统关键事件
            DomainEvent::StreamStarted { .. } => CRITICAL,
            DomainEvent::StreamEnded { .. } => CRITICAL,

            // High (P1): 用户交互
            DomainEvent::MessageCreated { .. } => HIGH,
            DomainEvent::MessageEdited { .. } => HIGH,
            DomainEvent::PostCreated { .. } => HIGH,
            DomainEvent::NotificationCreated { .. } => HIGH,

            // Normal (P2): 社交信号
            DomainEvent::ReactionAdded { .. } => NORMAL,
            DomainEvent::FollowAdded { .. } => NORMAL,

            // Low (P3): 索引和分析
            DomainEvent::SearchIndexUpdated { .. } => LOW,
            DomainEvent::MessageDeleted { .. } => LOW,
            DomainEvent::ReactionRemoved { .. } => LOW,
            DomainEvent::FollowRemoved { .. } => LOW,
            DomainEvent::PostUpdated { .. } => LOW,
            DomainEvent::PostDeleted { .. } => LOW,
            DomainEvent::StreamMessagePosted { .. } => NORMAL,
        }
    }
}
```

---

## 🚀 Task 1.2: events-service 核心实现

### 文件: backend/events-service/src/services/outbox.rs

```rust
//! Outbox 发布器 - 扫描待发布事件并推送到 Kafka

use uuid::Uuid;
use sqlx::PgPool;
use rdkafka::producer::FutureProducer;
use rdkafka::message::FutureRecord;
use std::time::Duration;
use tracing::{debug, error, info};
use nova_event_schema::OutboxEvent;

pub struct OutboxPublisher {
    db: PgPool,
    kafka_producer: FutureProducer,
    batch_size: i32,
    flush_interval_ms: u64,
}

impl OutboxPublisher {
    pub fn new(
        db: PgPool,
        kafka_producer: FutureProducer,
        batch_size: i32,
        flush_interval_ms: u64,
    ) -> Self {
        Self {
            db,
            kafka_producer,
            batch_size,
            flush_interval_ms,
        }
    }

    /// 启动后台发布任务 (永久运行)
    pub async fn start(self) {
        let mut ticker = tokio::time::interval(
            Duration::from_millis(self.flush_interval_ms)
        );

        loop {
            ticker.tick().await;

            match self.publish_batch().await {
                Ok(count) => {
                    if count > 0 {
                        debug!("Published {} outbox events", count);
                    }
                }
                Err(e) => {
                    error!("Failed to publish outbox batch: {}", e);
                    // 继续运行，不崩溃
                }
            }
        }
    }

    /// 发布一批待发布的事件
    async fn publish_batch(&self) -> Result<usize, Box<dyn std::error::Error>> {
        // 1. 查询未发布的事件
        let events: Vec<OutboxEvent> = sqlx::query_as(
            "SELECT id, aggregate_id, event_type, payload, priority, \
                    created_at, published_at, retry_count, last_error \
             FROM outbox_events \
             WHERE published_at IS NULL \
             ORDER BY priority ASC, created_at ASC \
             LIMIT $1"
        )
        .bind(self.batch_size)
        .fetch_all(&self.db)
        .await?;

        if events.is_empty() {
            return Ok(0);
        }

        info!("Publishing {} events to Kafka", events.len());

        // 2. 批量发送到 Kafka
        let mut send_futures = Vec::new();

        for event in &events {
            let topic = event.kafka_topic();
            let key = event.partition_key();
            let payload = serde_json::to_vec(&event)?;

            let record = FutureRecord::to(&topic)
                .key(&key)
                .payload(&payload)
                .timestamp(event.created_at.timestamp_millis());

            let future = self.kafka_producer.send(
                record,
                Duration::from_secs(5),
            );

            send_futures.push((event.id, future));
        }

        // 3. 等待所有发送完成
        let mut success_count = 0;

        for (event_id, future) in send_futures {
            match future.await {
                Ok(_) => {
                    // 更新发布时间戳
                    sqlx::query(
                        "UPDATE outbox_events \
                         SET published_at = NOW() \
                         WHERE id = $1"
                    )
                    .bind(event_id)
                    .execute(&self.db)
                    .await?;

                    success_count += 1;
                }
                Err((e, _)) => {
                    // 更新重试计数
                    sqlx::query(
                        "UPDATE outbox_events \
                         SET retry_count = retry_count + 1, \
                             last_error = $1 \
                         WHERE id = $2"
                    )
                    .bind(format!("Kafka error: {}", e))
                    .bind(event_id)
                    .execute(&self.db)
                    .await?;

                    error!("Failed to publish event {}: {}", event_id, e);
                }
            }
        }

        Ok(success_count)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // 注: 集成测试需要运行 PostgreSQL 和 Kafka
    // 见 backend/tests/outbox_publisher_test.rs
}
```

### 文件: backend/events-service/src/grpc/mod.rs (片段)

```rust
//! gRPC 服务实现

use tonic::{Request, Response, Status};
use uuid::Uuid;
use nova_events::events_service_server::EventsService;
use nova_events::{PublishEventRequest, PublishEventResponse};

pub struct EventsServiceImpl {
    db: sqlx::PgPool,
    // ... 其他字段
}

#[tonic::async_trait]
impl EventsService for EventsServiceImpl {
    async fn publish_event(
        &self,
        request: Request<PublishEventRequest>,
    ) -> Result<Response<PublishEventResponse>, Status> {
        let req = request.into_inner();

        // 1. 基本验证
        if req.event_type.is_empty() {
            return Err(Status::invalid_argument("event_type is required"));
        }

        // 2. 验证事件 schema (可选，但推荐)
        if !self.schema_registry.is_valid(&req.event_type, &req.payload) {
            return Err(Status::invalid_argument(
                format!("Invalid payload for event type: {}", req.event_type)
            ));
        }

        // 3. 保存到 Outbox 表
        let event_id = Uuid::new_v4();
        let aggregate_id = Uuid::parse_str(&req.aggregate_id)
            .map_err(|_| Status::invalid_argument("Invalid aggregate_id"))?;

        sqlx::query(
            "INSERT INTO outbox_events \
             (id, aggregate_id, event_type, payload, priority, created_at) \
             VALUES ($1, $2, $3, $4, $5, NOW())"
        )
        .bind(event_id)
        .bind(aggregate_id)
        .bind(&req.event_type)
        .bind(&req.payload)
        .bind(req.priority as i32)
        .execute(&self.db)
        .await
        .map_err(|e| Status::internal(format!("Failed to save event: {}", e)))?;

        Ok(Response::new(PublishEventResponse {
            event_id: event_id.to_string(),
            status: "QUEUED".to_string(),  // 等待 Outbox Publisher 发布
        }))
    }
}
```

---

## 🗄️ 数据库迁移

### 文件: backend/events-service/src/db/migrations/001_create_outbox_tables.sql

```sql
-- ===== Outbox Events Table (Core) =====
CREATE TABLE IF NOT EXISTS outbox_events (
    -- 主键和关联
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregate_id UUID NOT NULL,

    -- 事件类型和负载
    event_type VARCHAR(255) NOT NULL,
    payload JSONB NOT NULL,

    -- 元数据
    priority SMALLINT NOT NULL DEFAULT 2,  -- 0=Critical, 1=High, 2=Normal, 3=Low
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    published_at TIMESTAMPTZ,  -- NULL = 未发布

    -- 重试和错误处理
    retry_count INT NOT NULL DEFAULT 0,
    last_error TEXT,

    -- 索引优化
    CONSTRAINT check_priority CHECK (priority >= 0 AND priority <= 3),
    CONSTRAINT check_retry_count CHECK (retry_count >= 0)
);

-- 索引 1: 快速定位待发布事件
CREATE INDEX idx_outbox_unpublished
ON outbox_events(priority ASC, created_at ASC)
WHERE published_at IS NULL;

-- 索引 2: 按聚合根查询 (用于重放)
CREATE INDEX idx_outbox_aggregate
ON outbox_events(aggregate_id, event_type);

-- 索引 3: 按时间范围查询
CREATE INDEX idx_outbox_created
ON outbox_events(created_at DESC);

-- 索引 4: 监控和告警
CREATE INDEX idx_outbox_failed
ON outbox_events(retry_count DESC)
WHERE published_at IS NULL AND retry_count > 0;


-- ===== Event Schema Registry =====
CREATE TABLE IF NOT EXISTS event_schemas (
    event_type VARCHAR(255) NOT NULL,
    schema_version INT NOT NULL,
    schema_definition JSONB NOT NULL,  -- JSON Schema
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (event_type, schema_version),
    CONSTRAINT check_version CHECK (schema_version > 0)
);

-- 创建初始版本
INSERT INTO event_schemas (event_type, schema_version, schema_definition)
VALUES (
    'MessageCreated',
    1,
    '{
        "type": "object",
        "properties": {
            "message_id": {"type": "string", "format": "uuid"},
            "sender_id": {"type": "string", "format": "uuid"},
            "recipient_id": {"type": "string", "format": "uuid"},
            "content": {"type": "string"}
        },
        "required": ["message_id", "sender_id", "recipient_id", "content"]
    }'::jsonb
);


-- ===== Kafka Topic Metadata =====
CREATE TABLE IF NOT EXISTS kafka_topics (
    topic_name VARCHAR(255) PRIMARY KEY,
    event_type VARCHAR(255) NOT NULL,
    partition_count INT NOT NULL DEFAULT 3,
    replication_factor INT NOT NULL DEFAULT 2,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(event_type),
    CONSTRAINT check_partitions CHECK (partition_count > 0),
    CONSTRAINT check_replication CHECK (replication_factor > 0)
);

-- 创建初始 topics
INSERT INTO kafka_topics (topic_name, event_type, partition_count)
VALUES
    ('nova_events_messagecreated', 'MessageCreated', 3),
    ('nova_events_reactionadded', 'ReactionAdded', 3),
    ('nova_events_followadded', 'FollowAdded', 3),
    ('nova_events_postcreated', 'PostCreated', 3)
ON CONFLICT DO NOTHING;
```

---

## ✅ 单元测试模板

### 文件: backend/events-service/src/services/outbox_test.rs

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use sqlx::postgres::PgPoolOptions;
    use testcontainers::clients::Cli;
    use testcontainers::images::postgres::Postgres;

    async fn setup_db() -> PgPool {
        let docker = Cli::default();
        let postgres = docker.run(Postgres::default());

        let connection_string = format!(
            "postgresql://postgres:postgres@{}",
            postgres.get_host_port_ipv4(5432)
        );

        let pool = PgPoolOptions::new()
            .connect(&connection_string)
            .await
            .unwrap();

        // 运行迁移
        sqlx::raw_sql(MIGRATIONS)
            .execute(&pool)
            .await
            .unwrap();

        pool
    }

    #[tokio::test]
    async fn test_outbox_event_persistence() {
        let db = setup_db().await;
        let event_id = Uuid::new_v4();
        let aggregate_id = Uuid::new_v4();

        sqlx::query(
            "INSERT INTO outbox_events \
             (id, aggregate_id, event_type, payload, created_at) \
             VALUES ($1, $2, $3, $4, NOW())"
        )
        .bind(event_id)
        .bind(aggregate_id)
        .bind("MessageCreated")
        .bind(serde_json::json!({"test": "data"}))
        .execute(&db)
        .await
        .unwrap();

        // 验证插入
        let row: (Uuid, bool) = sqlx::query_as(
            "SELECT id, published_at IS NULL FROM outbox_events WHERE id = $1"
        )
        .bind(event_id)
        .fetch_one(&db)
        .await
        .unwrap();

        assert_eq!(row.0, event_id);
        assert!(row.1);  // published_at IS NULL
    }

    #[tokio::test]
    async fn test_outbox_query_performance() {
        // 插入 10000 个事件，验证查询速度 < 100ms
        // ...
    }
}
```

---

## 🎬 下一步行动

1. **立即复制代码**:
   ```bash
   # 1. 创建文件
   touch backend/libs/event-schema/src/outbox.rs
   touch backend/libs/event-schema/src/events.rs
   touch backend/events-service/src/services/outbox.rs

   # 2. 复制上面的内容
   # 3. 修改 Cargo.toml 依赖
   # 4. 运行 cargo build
   ```

2. **运行数据库迁移**:
   ```bash
   sqlx migrate run --database-url postgresql://...
   ```

3. **启动本地测试**:
   ```bash
   cargo test --package events-service
   ```

4. **性能基准**:
   ```bash
   # 测试 Outbox 发布延迟
   time cargo run --release --bin events-service
   ```

---

**预计完成**:
- Task 1.1 (Outbox): 16h
- Task 1.2 (events-service): 32h

准备开始? 🚀
