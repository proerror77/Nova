# Nova 事件驱动架构设计

## 概述

所有服务间通信通过 Kafka 事件总线进行，实现完全解耦的微服务架构。

## Kafka Topics 约定（当前实现）

| Topic / Pattern | 用途 | Producers | Consumers |
|-----------------|------|-----------|-----------|
| `${KAFKA_TOPIC_PREFIX}.<aggregate>.events` | Outbox 领域事件 | 使用 transactional-outbox 的服务 | 下游缓存/搜索/分析 |
| `nova.identity.events` (`KAFKA_IDENTITY_EVENTS_TOPIC`) | 身份事件（payload + event_type header） | identity-service | graph-service, search-service, realtime-chat-service |
| `nova.media.events` (`KAFKA_MEDIA_EVENTS_TOPIC` / `KAFKA_EVENTS_TOPIC`) | 媒体上传事件 | media-service | content-service, analytics-service, thumb-worker |
| `nova.message.events` (`KAFKA_MESSAGE_EVENTS_TOPIC`) | 消息索引事件（event_type: message.persisted/message.deleted） | messaging pipeline | search-service |

> 兼容说明：`message_persisted` / `message_deleted` 旧主题仍可被消费用于平滑迁移。

---

## 1. Content Events (`nova.content.events` topic)

### 1.1 PostCreated

**发布者**: content-service
**消费者**: feed-service, search-service, analytics-service
**event_type**: `content.post.created`

**Payload** (JSON):
```json
{
  "post_id": "uuid",
  "user_id": "uuid",
  "caption": "text",
  "media_type": "image|video|none",
  "status": "published",
  "created_at": "2025-01-15T10:30:00Z"
}
```

**Partition Key**: aggregate_id (`post_id`) via Kafka key

**发布时机**:
```rust
// content-service/src/services/posts.rs
pub async fn create_post(...) -> Result<Post> {
    let mut tx = self.pool.begin().await?;
    let post = self.db.insert_post(&mut tx, ...).await?;

    // Publish via transactional outbox (same transaction)
    publish_post_created(&mut tx, outbox, &post).await?;

    tx.commit().await?;
    Ok(post)
}
```

**消费示例** (feed-service):
```rust
// feed-service/src/consumers/content_consumer.rs
pub async fn handle_post_created(&self, message: &BorrowedMessage<'_>) -> Result<()> {
    let event_type = header_value(message, "event_type");
    if event_type != Some("content.post.created") {
        return Ok(());
    }

    let event: serde_json::Value = serde_json::from_slice(message.payload().unwrap_or_default())?;
    let user_id = event.get("user_id").and_then(|v| v.as_str()).unwrap_or_default();
    let post_id = event.get("post_id").and_then(|v| v.as_str()).unwrap_or_default();
    let created_at = event
        .get("created_at")
        .and_then(|v| v.as_str())
        .and_then(|v| chrono::DateTime::parse_from_rfc3339(v).ok())
        .map(|dt| dt.timestamp())
        .unwrap_or_else(|| chrono::Utc::now().timestamp());

    // 1. 获取用户的粉丝列表
    let followers = self.get_followers(user_id).await?;

    // 2. 为每个粉丝更新 feed
    for follower_id in followers {
        self.redis.zadd(
            format!("feed:{}", follower_id),
            created_at,
            post_id
        ).await?;
    }

    // 3. 更新本地内容缓存（去中心化）
    self.cache_post_summary(&event).await?;

    Ok(())
}
```

---

### 1.2 PostStatusUpdated

**发布者**: content-service
**消费者**: feed-service, search-service
**event_type**: `content.post.status_updated`

**Payload** (JSON):
```json
{
  "post_id": "uuid",
  "user_id": "uuid",
  "new_status": "published|archived|deleted",
  "updated_at": "2025-01-15T10:30:00Z"
}
```

---

### 1.3 PostDeleted

**发布者**: content-service
**消费者**: feed-service, search-service, analytics-service
**event_type**: `content.post.deleted`

**Payload** (JSON):
```json
{
  "post_id": "uuid",
  "user_id": "uuid",
  "deleted_at": "2025-01-15T10:30:00Z"
}
```

**消费示例** (feed-service):
```rust
pub async fn handle_post_deleted(&self, event: serde_json::Value) -> Result<()> {
    // 1. 从所有用户的 feed 中移除
    let followers = self.get_followers(&event.user_id).await?;
    for follower_id in followers {
        self.redis.zrem(
            format!("feed:{}", follower_id),
            &event.post_id
        ).await?;
    }

    // 2. 删除本地缓存
    self.cache.delete(&event.post_id).await?;

    Ok(())
}
```

---

## 2. Media Events (`nova.media.events` topic)

### 2.1 MediaUploaded

**发布者**: media-service
**消费者**: content-service
**Topic**: `KAFKA_MEDIA_EVENTS_TOPIC` / `KAFKA_EVENTS_TOPIC` (default `nova.media.events`)
**Header**: `event_type = media.upload.completed`

**Payload** (JSON):
```json
{
  "upload_id": "uuid",
  "media_id": "uuid",
  "user_id": "uuid",
  "file_name": "example.jpg",
  "size_bytes": 123456,
  "uploaded_at": "2025-01-15T10:30:00Z"
}
```

**发布时机**:
```rust
// media-service/src/kafka/events.rs
let producer = MediaEventsProducer::new(brokers, topic)?;
producer.publish_media_uploaded(upload).await?;
```

**消费示例** (content-service):
```rust
// content-service/src/consumers/media_consumer.rs
pub async fn handle_media_uploaded(&self, message: &BorrowedMessage<'_>) -> Result<()> {
    let event: serde_json::Value = serde_json::from_slice(message.payload().unwrap_or_default())?;
    let user_id = event.get("user_id").and_then(|v| v.as_str()).unwrap_or_default();
    let media_id = event.get("media_id").and_then(|v| v.as_str()).unwrap_or_default();

    // 媒体暂存，等待用户创建 post 时关联
    self.cache.set(
        format!("pending_media:{}", user_id),
        media_id,
        Duration::from_secs(3600)
    ).await?;

    Ok(())
}
```

---

## 3. User Events (`nova.identity.events` topic)

> identity-service emits payload-only events via transactional-outbox with `event_type` headers.

### 3.1 identity.user.created (legacy: UserCreatedEvent)

**发布者**: identity-service
**消费者**: analytics-service, ranking-service

```json
{
  "user_id": "uuid",
  "username": "username",
  "email": "user@example.com",
  "created_at": "2025-01-15T10:30:00Z"
}
```

---

### 3.2 identity.user.profile_updated (legacy: UserProfileUpdatedEvent)

**发布者**: identity-service
**消费者**: feed-service, search-service

```json
{
  "user_id": "uuid",
  "username": "username",
  "display_name": "Display Name",
  "avatar_url": "https://cdn...",
  "is_verified": false,
  "follower_count": 0,
  "updated_at": "2025-01-15T10:30:00Z"
}
```

---

### 3.3 identity.user.deleted (legacy: UserDeletedEvent)

**发布者**: identity-service
**消费者**: graph-service, search-service, analytics-service

```json
{
  "user_id": "uuid",
  "deleted_at": "2025-01-15T10:30:00Z",
  "soft_delete": true
}
```

---

## 4. Messaging Index Events (`nova.message.events`)

这些主题用于搜索索引同步（严格 E2EE 会话不应包含明文内容）。

### 4.1 message.persisted (legacy: message_persisted)

**发布者**: messaging pipeline
**消费者**: search-service

```json
{
  "message_id": "uuid",
  "conversation_id": "uuid",
  "sender_id": "uuid",
  "content": "optional plaintext (if search_enabled)",
  "created_at": "2025-01-15T10:30:00Z"
}
```

### 4.2 message.deleted (legacy: message_deleted)

**发布者**: messaging pipeline
**消费者**: search-service

```json
{
  "message_id": "uuid",
  "conversation_id": "uuid",
  "deleted_at": "2025-01-15T10:30:00Z"
}
```

---

## 实施指南

### Step 1: content-service 发布事件

```rust
// content-service/src/services/posts.rs
publish_post_created(&mut tx, outbox, &post).await?;

// content-service/src/main.rs
let outbox_publisher = KafkaOutboxPublisher::new(producer, "nova".to_string());
let outbox_processor = OutboxProcessor::new(
    outbox_repo,
    outbox_publisher,
    100,                    // batch_size
    Duration::from_secs(5), // poll_interval
    5,                      // max_retries
);
```

---

### Step 2: feed-service 消费事件

```rust
// feed-service/src/kafka/consumer.rs
consumer.subscribe(&["nova.content.events"])?;
// Use Kafka header `event_type` to route payloads, then parse JSON payload.
```

---

### Step 3: 环境变量配置

```yaml
# content-service-env-patch.yaml
- name: KAFKA_BROKERS
  value: "kafka.nova-staging.svc.cluster.local:9092"
- name: KAFKA_TOPIC_PREFIX
  value: "nova" # Some services use this; content-service currently hardcodes "nova"
```

```yaml
# feed-service-env-patch.yaml
- name: KAFKA_BROKERS
  value: "kafka.nova-staging.svc.cluster.local:9092"
- name: KAFKA_GROUP_ID
  value: "feed-service-group"
- name: KAFKA_TOPICS
  value: "nova.content.events"
```

---

## 事件顺序保证

### Partition Key 策略

| Event | Partition Key | 理由 |
|-------|---------------|------|
| content.post.* | post_id | Outbox uses aggregate_id as Kafka key |
| identity events | user_id | User lifecycle ordered per user |
| media.upload.completed | upload_id | 同一上传任务的事件有序 |
| message.persisted | conversation_id | 同一会话的消息有序 |

### 幂等性实现

```rust
// feed-service/src/consumers/content_consumer.rs
pub async fn handle_post_created(&self, message: &BorrowedMessage<'_>) -> Result<()> {
    // 检查是否已处理（幂等性）
    let event_id = header_value(message, "event_id").unwrap_or("unknown");
    let idempotency_key = format!("processed:{}", event_id);

    if self.redis.exists(&idempotency_key).await? {
        tracing::info!("Event already processed, skipping");
        return Ok(());
    }

    // 处理事件
    let payload: serde_json::Value =
        serde_json::from_slice(message.payload().unwrap_or_default())?;
    self.process_event(&payload).await?;

    // 标记已处理（TTL 7天）
    self.redis.setex(&idempotency_key, 604800, "1").await?;

    Ok(())
}
```

---

## 监控和告警

### Kafka Lag 监控

```yaml
# prometheus-kafka-exporter.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-lag-exporter
spec:
  template:
    spec:
      containers:
      - name: kafka-lag-exporter
        image: seglo/kafka-lag-exporter:0.8.2
        env:
        - name: KAFKA_BROKERS
          value: "kafka:9092"
```

### 告警规则

```yaml
# prometheus-rules.yaml
groups:
- name: kafka-lag
  rules:
  - alert: KafkaConsumerLagHigh
    expr: kafka_consumer_lag > 1000
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Kafka consumer {{ $labels.group }} lag is {{ $value }}"
```

---

## 回滚策略

如果事件驱动架构出现问题，可以临时启用同步调用：

```yaml
# 紧急回滚：恢复 feed-service 对 content-service 的直接调用
- feed-service-init-fix.yaml
```

```rust
// feed-service feature flag
if env::var("ENABLE_DIRECT_CALL").is_ok() {
    // 直接调用 content-service
    let post = content_client.get_post(post_id).await?;
} else {
    // 从本地缓存读取（事件驱动）
    let post = self.cache.get(post_id).await?;
}
```

---

## 测试策略

### 1. 单元测试

```rust
#[tokio::test]
async fn test_post_created_event() {
    let consumer = MockKafkaConsumer::new();
    let event = PostCreated {
        post_id: "123".into(),
        user_id: "456".into(),
        // ...
    };

    consumer.handle_post_created(event).await.unwrap();

    assert!(consumer.cache.contains_key("123"));
}
```

### 2. 集成测试

```bash
# 发送测试事件到 Kafka
kafka-console-producer --bootstrap-server kafka:9092 --topic nova.content.events
> {"post_id":"test123","user_id":"user456",...}

# 检查 feed-service 是否消费
kubectl logs -f feed-service-xxx | grep "test123"
```

### 3. 性能测试

```bash
# 压测 nova.content.events topic
kafka-producer-perf-test \
  --topic nova.content.events \
  --num-records 10000 \
  --record-size 1000 \
  --throughput 1000 \
  --producer-props bootstrap.servers=kafka:9092
```

---

## 迁移清单

### Phase 1: JWT 认证 ✅
- [x] messaging-service 移除 wait-for-identity-service
- [x] realtime-chat-service 移除 wait-for-identity-service
- [ ] messaging-service 实现 JWT 验证
- [ ] realtime-chat-service 实现 JWT 验证

### Phase 2: Content Events ✅
- [x] Kafka 添加 nova.content.events topic (6 partitions)
- [x] feed-service 移除 wait-for-content-service
- [ ] content-service 发布 PostCreated 事件
- [ ] content-service 发布 PostUpdated 事件
- [ ] content-service 发布 PostDeleted 事件
- [ ] feed-service 订阅 nova.content.events
- [ ] feed-service 维护本地内容索引
- [ ] 测试事件流

### Phase 3: Media Events ✅
- [x] Kafka 添加 nova.media.events topic (3 partitions)
- [x] media-service 移除 wait-for-content-service
- [ ] media-service 发布 MediaUploaded 事件
- [ ] content-service 订阅 nova.media.events
- [ ] 测试媒体上传流程

---

## 预期收益

| 指标 | 当前 | 目标 | 改进 |
|------|------|------|------|
| 服务可用性 | 链式依赖，99.0% | 独立部署，99.9% | +0.9% |
| 故障隔离 | 一个服务故障影响全链路 | 故障隔离 | 100% |
| 部署频率 | 每周1次 | 每天多次 | 10x |
| 吞吐量 | 受最慢服务限制 | 各服务独立扩展 | 3-5x |
| 延迟 | 50ms (同步) | 100-500ms (异步) | -2x ~ -10x |

**总结**: 延迟略有增加，但可用性、可扩展性和开发速度大幅提升。
