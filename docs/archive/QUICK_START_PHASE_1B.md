# Phase 1B 快速启动指南

**本文档**: 立即可执行的代码任务清单
**目标**: 指导工程师从 0-1 完成每个模块
**时间**: 根据并行度，4-6 周完成

---

## 🚀 立即启动: events-service (Week 1)

### 步骤 1: 扩展事件协议库

```bash
# 1. 编辑事件定义库
nano backend/libs/event-schema/src/lib.rs
```

添加以下内容:

```rust
// 统一 OutboxEvent 结构
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OutboxEvent {
    pub id: Uuid,
    pub aggregate_id: Uuid,
    pub event_type: String,
    pub payload: serde_json::Value,
    pub created_at: DateTime<Utc>,
    pub published_at: Option<DateTime<Utc>>,
    pub retry_count: i32,
    pub last_error: Option<String>,
}

// 事件优先级
#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum EventPriority {
    Critical = 0,
    High = 1,
    Normal = 2,
    Low = 3,
}

// 所有事件类型 (业务驱动的完整清单)
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "event_type")]
pub enum DomainEvent {
    // Messaging Events
    MessageCreated {
        message_id: Uuid,
        sender_id: Uuid,
        recipient_id: Uuid,
        content: String,
    },
    MessageEdited {
        message_id: Uuid,
        editor_id: Uuid,
        new_content: String,
    },
    MessageDeleted {
        message_id: Uuid,
        deleter_id: Uuid,
    },

    // Reaction Events
    ReactionAdded {
        target_id: Uuid,  // message/post/comment id
        target_type: String,  // "message"/"post"/"comment"
        user_id: Uuid,
        emoji: String,
    },
    ReactionRemoved {
        target_id: Uuid,
        user_id: Uuid,
        emoji: String,
    },

    // Follow Events
    FollowAdded {
        follower_id: Uuid,
        followee_id: Uuid,
    },

    // Content Events
    PostCreated {
        post_id: Uuid,
        author_id: Uuid,
        title: String,
        tags: Vec<String>,
    },

    PostUpdated {
        post_id: Uuid,
        editor_id: Uuid,
    },

    PostDeleted {
        post_id: Uuid,
        deleter_id: Uuid,
    },

    // Add more events as needed...
}
```

### 步骤 2: 创建 Outbox 后台任务

```bash
touch backend/events-service/src/services/outbox.rs
```

```rust
// 完整的 Outbox 发布器
use tokio::time::{interval, Duration};
use sqlx::PgPool;
use rdkafka::producer::FutureProducer;

pub struct OutboxPublisher {
    db: PgPool,
    kafka_producer: FutureProducer,
    batch_size: i32,
    flush_interval_ms: u64,
}

impl OutboxPublisher {
    pub async fn start(self) {
        let mut ticker = interval(Duration::from_millis(self.flush_interval_ms));

        loop {
            ticker.tick().await;

            if let Err(e) = self.publish_batch().await {
                tracing::error!("Failed to publish outbox batch: {}", e);
            }
        }
    }

    async fn publish_batch(&self) -> Result<()> {
        // 1. 查询未发布的事件
        let events: Vec<OutboxEvent> = sqlx::query_as(
            "SELECT * FROM outbox_events
             WHERE published_at IS NULL
             ORDER BY created_at ASC
             LIMIT $1"
        )
        .bind(self.batch_size)
        .fetch_all(&self.db)
        .await?;

        // 2. 批量发送到 Kafka
        let mut send_futures = Vec::new();

        for event in &events {
            let topic = format!("nova_events_{}", event.event_type);
            let key = event.aggregate_id.to_string();
            let payload = serde_json::to_vec(&event.payload)?;

            let future = self.kafka_producer.send(
                rdkafka::message::FutureRecord::to(&topic)
                    .key(&key)
                    .payload(&payload),
                Duration::from_secs(5),
            );

            send_futures.push((event.id, future));
        }

        // 3. 等待所有发送完成
        for (event_id, future) in send_futures {
            match future.await {
                Ok(_) => {
                    // 标记为已发布
                    sqlx::query(
                        "UPDATE outbox_events SET published_at = NOW() WHERE id = $1"
                    )
                    .bind(event_id)
                    .execute(&self.db)
                    .await?;
                }
                Err(e) => {
                    // 更新重试计数和错误信息
                    sqlx::query(
                        "UPDATE outbox_events
                         SET retry_count = retry_count + 1,
                             last_error = $1
                         WHERE id = $2"
                    )
                    .bind(e.to_string())
                    .bind(event_id)
                    .execute(&self.db)
                    .await?;
                }
            }
        }

        Ok(())
    }
}
```

### 步骤 3: 实现 events-service gRPC

编辑 `backend/events-service/src/grpc.rs`:

```rust
#[tonic::async_trait]
impl EventsService for EventsServiceImpl {
    async fn publish_event(
        &self,
        request: tonic::Request<PublishEventRequest>,
    ) -> Result<tonic::Response<PublishEventResponse>, tonic::Status> {
        let req = request.into_inner();

        // 1. 验证 schema
        self.validate_event_schema(&req.event_type, &req.payload)?;

        // 2. 保存到 Outbox
        let event_id = Uuid::new_v4();
        sqlx::query(
            "INSERT INTO outbox_events (id, aggregate_id, event_type, payload, created_at)
             VALUES ($1, $2, $3, $4, NOW())"
        )
        .bind(event_id)
        .bind(req.aggregate_id)
        .bind(&req.event_type)
        .bind(&req.payload)
        .execute(&self.db)
        .await
        .map_err(|e| tonic::Status::internal(e.to_string()))?;

        Ok(tonic::Response::new(PublishEventResponse {
            event_id: event_id.to_string(),
        }))
    }
}
```

---

## 📋 执行清单

### Week 1 任务

- [ ] Task 1.1: Outbox 模式扩展 (Serena + 1 工程师, 16h)
  - [ ] 扩展 event-schema
  - [ ] 添加数据库迁移
  - [ ] 本地测试

- [ ] Task 1.2: events-service 实现 (Serena + 1 工程师, 32h)
  - [ ] PublishEvent RPC
  - [ ] SubscribeToEvents RPC
  - [ ] Outbox 后台任务
  - [ ] 集成测试 (5 个测试用例)

- [ ] Task 1.3: messaging-service user_id 提取 (1 工程师, 8h)
  - [ ] 添加 extract_user_id 函数
  - [ ] 在所有 RPC 中应用
  - [ ] 单元测试

### Week 2 任务

- [ ] Task 2.1: notification-service CRUD (2 工程师, 24h)
  - [ ] 数据库 schema
  - [ ] CRUD RPC 实现
  - [ ] 单元测试

- [ ] Task 2.2: search-service 实现 (2 工程师, 20h)
  - [ ] Elasticsearch 集成
  - [ ] 搜索 RPC 实现
  - [ ] 建议和热搜

---

## 🔧 本地开发环境

```bash
# 1. 启动 Docker Compose 服务
docker-compose -f docker-compose.dev.yml up -d

# 2. 运行数据库迁移
sqlx migrate run --database-url postgresql://...

# 3. 编译 events-service
cd backend/events-service
cargo build

# 4. 运行 gRPC 服务
cargo run

# 5. 在另一个终端测试
grpcurl -plaintext \
  -d '{"event_type":"message_created","aggregate_id":"...","payload":{...}}' \
  localhost:50051 events.EventsService/PublishEvent
```

---

## 📞 常见问题

**Q: Outbox 表在 PostgreSQL 中的性能影响?**
A: 优化方案:
- 使用分区表 (by date) 周期归档
- 发布成功 30 天后删除
- 创建索引: `idx_unpublished (published_at, created_at)`

**Q: Kafka Topic 自动创建?**
A: 是的，通过 Kafka broker 的 `auto.create.topics.enable=true`

**Q: 如何处理 duplicate events?**
A: 使用 `event_id` 作为幂等键，消费端记录 Redis: `processed_events:{event_id}`

**Q: 网络分区时怎么办?**
A:
1. 事件堆积在 Outbox 表
2. 网络恢复后自动发送
3. 消费端验证幂等性

---

## 🎯 验收标准

- ✅ Outbox 表无未发布事件 (5+ 分钟)
- ✅ Kafka 消息在 1 秒内出现
- ✅ 不存在重复事件
- ✅ 事件顺序保证 (per aggregate)
- ✅ 端到端延迟 < 500ms

---

## 💬 获取帮助

遇到问题?
1. 检查 `/Users/proerror/Documents/nova/IMPLEMENTATION_PLAN_PHASE_1B.md` 详细设计
2. 查看代码注释和错误信息
3. 运行 `cargo test` 验证逻辑
4. 查看日志: `tail -f logs/events-service.log`

祝你编码愉快! 🚀
