# Nova 事件驱动架构设计

## 概述

所有服务间通信通过 Kafka 事件总线进行，实现完全解耦的微服务架构。

## Kafka Topics 配置

| Topic | Partitions | Replication | 用途 | Producers | Consumers |
|-------|------------|-------------|------|-----------|-----------|
| **content-events** | 6 | 1 | 内容生命周期事件 | content-service | feed-service, search-service, analytics-service |
| **media-events** | 3 | 1 | 媒体上传事件 | media-service | content-service |
| **user-events** | 3 | 1 | 用户生命周期事件 | identity-service | analytics-service, ranking-service |
| **messaging-events** | 3 | 1 | 消息事件 | messaging-service | realtime-chat-service, notification-service |
| **notification-events** | 2 | 1 | 通知事件 | notification-service | (external) |
| **analytics-events** | 6 | 1 | 分析事件 | all services | analytics-service |
| **feed-updates** | 3 | 1 | Feed 更新事件 | feed-service | (external) |
| **ranking-updates** | 3 | 1 | 排名更新事件 | ranking-service | feed-service |
| **trust-safety-events** | 3 | 1 | 内容审核事件 | trust-safety-service | content-service |
| **realtime-chat** | 3 | 1 | 实时聊天事件 | realtime-chat-service | messaging-service |

---

## 1. Content Events (content-events topic)

### 1.1 PostCreated

**发布者**: content-service
**消费者**: feed-service, search-service, analytics-service

```protobuf
message PostCreated {
  string post_id = 1;
  string user_id = 2;
  string content = 3;
  PostType type = 4;  // TEXT, IMAGE, VIDEO, REEL
  PostVisibility visibility = 5;  // PUBLIC, PRIVATE, FOLLOWERS_ONLY
  repeated string tags = 6;
  google.protobuf.Timestamp created_at = 7;

  // 用于 Kafka 分区
  string partition_key = user_id;
}
```

**发布时机**:
```rust
// content-service/src/services/post_service.rs
pub async fn create_post(&self, req: CreatePostRequest) -> Result<Post> {
    // 1. 写入数据库
    let post = self.db.insert_post(&req).await?;

    // 2. 发布事件到 Kafka
    let event = PostCreated {
        post_id: post.id.clone(),
        user_id: post.user_id.clone(),
        content: post.content.clone(),
        // ...
    };
    self.kafka_producer.send("content-events", &event).await?;

    Ok(post)
}
```

**消费示例** (feed-service):
```rust
// feed-service/src/consumers/content_consumer.rs
pub async fn handle_post_created(&self, event: PostCreated) -> Result<()> {
    // 1. 获取用户的粉丝列表
    let followers = self.get_followers(&event.user_id).await?;

    // 2. 为每个粉丝更新 feed
    for follower_id in followers {
        self.redis.zadd(
            format!("feed:{}", follower_id),
            event.created_at.timestamp(),
            &event.post_id
        ).await?;
    }

    // 3. 更新本地内容缓存（去中心化）
    self.cache_post_summary(&event).await?;

    Ok(())
}
```

---

### 1.2 PostUpdated

**发布者**: content-service
**消费者**: feed-service, search-service

```protobuf
message PostUpdated {
  string post_id = 1;
  string user_id = 2;
  optional string content = 3;  // 如果修改了内容
  repeated string tags = 4;
  google.protobuf.Timestamp updated_at = 5;
}
```

---

### 1.3 PostDeleted

**发布者**: content-service
**消费者**: feed-service, search-service, analytics-service

```protobuf
message PostDeleted {
  string post_id = 1;
  string user_id = 2;
  google.protobuf.Timestamp deleted_at = 3;
}
```

**消费示例** (feed-service):
```rust
pub async fn handle_post_deleted(&self, event: PostDeleted) -> Result<()> {
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

## 2. Media Events (media-events topic)

### 2.1 MediaUploaded

**发布者**: media-service
**消费者**: content-service

```protobuf
message MediaUploaded {
  string media_id = 1;
  string post_id = 2;  // 关联的 post（可能为空，如果是先上传后创建 post）
  string user_id = 3;
  MediaType type = 4;  // IMAGE, VIDEO, AUDIO
  string url = 5;  // S3 URL
  string thumbnail_url = 6;
  MediaMetadata metadata = 7;
  google.protobuf.Timestamp uploaded_at = 8;
}

message MediaMetadata {
  int32 width = 1;
  int32 height = 2;
  int64 size_bytes = 3;
  string mime_type = 4;
  optional int32 duration_seconds = 5;  // for video/audio
}
```

**发布时机**:
```rust
// media-service/src/services/upload_service.rs
pub async fn upload_media(&self, file: MultipartFile) -> Result<Media> {
    // 1. 上传到 S3
    let url = self.s3.upload(&file).await?;

    // 2. 生成缩略图
    let thumbnail_url = self.generate_thumbnail(&url).await?;

    // 3. 写入数据库
    let media = self.db.insert_media(&url, &thumbnail_url).await?;

    // 4. 发布事件（不等待 content-service）
    let event = MediaUploaded {
        media_id: media.id.clone(),
        url: url.clone(),
        // ...
    };
    self.kafka_producer.send("media-events", &event).await?;

    Ok(media)
}
```

**消费示例** (content-service):
```rust
// content-service/src/consumers/media_consumer.rs
pub async fn handle_media_uploaded(&self, event: MediaUploaded) -> Result<()> {
    if let Some(post_id) = &event.post_id {
        // 关联媒体到 post
        self.db.attach_media_to_post(post_id, &event.media_id).await?;

        // 可选：发布 PostUpdated 事件
        self.kafka_producer.send("content-events", &PostUpdated {
            post_id: post_id.clone(),
            // ...
        }).await?;
    } else {
        // 媒体暂存，等待用户创建 post 时关联
        self.cache.set(
            format!("pending_media:{}", event.user_id),
            &event.media_id,
            Duration::from_secs(3600)
        ).await?;
    }

    Ok(())
}
```

---

## 3. User Events (user-events topic)

### 3.1 UserRegistered

**发布者**: identity-service
**消费者**: analytics-service, ranking-service

```protobuf
message UserRegistered {
  string user_id = 1;
  string username = 2;
  string email = 3;
  google.protobuf.Timestamp registered_at = 4;
}
```

---

### 3.2 UserProfileUpdated

**发布者**: identity-service
**消费者**: feed-service, search-service

```protobuf
message UserProfileUpdated {
  string user_id = 1;
  optional string username = 2;
  optional string display_name = 3;
  optional string avatar_url = 4;
  google.protobuf.Timestamp updated_at = 5;
}
```

---

## 4. Messaging Events (messaging-events topic)

### 4.1 MessageSent

**发布者**: messaging-service
**消费者**: realtime-chat-service, notification-service

```protobuf
message MessageSent {
  string message_id = 1;
  string conversation_id = 2;
  string sender_id = 3;
  repeated string recipient_ids = 4;
  string content = 5;
  MessageType type = 6;  // TEXT, IMAGE, VIDEO, AUDIO
  google.protobuf.Timestamp sent_at = 7;
}
```

**消费示例** (realtime-chat-service):
```rust
// realtime-chat-service/src/consumers/message_consumer.rs
pub async fn handle_message_sent(&self, event: MessageSent) -> Result<()> {
    // 实时推送给在线用户
    for recipient_id in &event.recipient_ids {
        if let Some(websocket) = self.get_user_connection(recipient_id).await? {
            websocket.send_json(&event).await?;
        }
    }

    Ok(())
}
```

---

## 实施指南

### Step 1: content-service 发布事件

```rust
// content-service/Cargo.toml
[dependencies]
rdkafka = "0.36"
prost = "0.13"

// content-service/src/kafka/producer.rs
use rdkafka::producer::{FutureProducer, FutureRecord};

pub struct KafkaProducer {
    producer: FutureProducer,
}

impl KafkaProducer {
    pub fn new(brokers: &str) -> Result<Self> {
        let producer: FutureProducer = rdkafka::config::ClientConfig::new()
            .set("bootstrap.servers", brokers)
            .set("message.timeout.ms", "5000")
            .create()?;

        Ok(Self { producer })
    }

    pub async fn send_post_created(&self, event: &PostCreated) -> Result<()> {
        let payload = prost::Message::encode_to_vec(event);
        let record = FutureRecord::to("content-events")
            .key(&event.user_id)  // 分区键：同一用户的事件有序
            .payload(&payload);

        self.producer.send(record, Duration::from_secs(0)).await
            .map_err(|(err, _)| err)?;

        Ok(())
    }
}
```

---

### Step 2: feed-service 消费事件

```rust
// feed-service/src/kafka/consumer.rs
use rdkafka::consumer::{Consumer, StreamConsumer};
use rdkafka::Message;

pub struct ContentEventsConsumer {
    consumer: StreamConsumer,
}

impl ContentEventsConsumer {
    pub fn new(brokers: &str, group_id: &str) -> Result<Self> {
        let consumer: StreamConsumer = rdkafka::config::ClientConfig::new()
            .set("bootstrap.servers", brokers)
            .set("group.id", group_id)
            .set("enable.auto.commit", "true")
            .set("auto.offset.reset", "earliest")
            .create()?;

        consumer.subscribe(&["content-events"])?;

        Ok(Self { consumer })
    }

    pub async fn run(&self) {
        loop {
            match self.consumer.recv().await {
                Ok(msg) => {
                    if let Some(payload) = msg.payload() {
                        let event = PostCreated::decode(payload)?;
                        self.handle_event(event).await?;
                    }
                }
                Err(e) => tracing::error!("Kafka error: {}", e),
            }
        }
    }
}
```

---

### Step 3: 环境变量配置

```yaml
# content-service-env-patch.yaml
- name: KAFKA_BROKERS
  value: "kafka.nova-staging.svc.cluster.local:9092"
- name: KAFKA_TOPIC_CONTENT_EVENTS
  value: "content-events"
```

```yaml
# feed-service-env-patch.yaml
- name: KAFKA_BROKERS
  value: "kafka.nova-staging.svc.cluster.local:9092"
- name: KAFKA_GROUP_ID
  value: "feed-service-group"
- name: KAFKA_TOPICS
  value: "content-events,ranking-updates"
```

---

## 事件顺序保证

### Partition Key 策略

| Event | Partition Key | 理由 |
|-------|---------------|------|
| PostCreated | user_id | 同一用户的 post 按时间顺序处理 |
| PostUpdated | post_id | 同一 post 的更新按顺序处理 |
| MediaUploaded | user_id | 同一用户的媒体按上传顺序处理 |
| MessageSent | conversation_id | 同一会话的消息有序 |

### 幂等性实现

```rust
// feed-service/src/consumers/content_consumer.rs
pub async fn handle_post_created(&self, event: PostCreated) -> Result<()> {
    // 检查是否已处理（幂等性）
    let idempotency_key = format!("processed:{}:{}", event.post_id, event.created_at);

    if self.redis.exists(&idempotency_key).await? {
        tracing::info!("Event already processed, skipping");
        return Ok(());
    }

    // 处理事件
    self.process_event(&event).await?;

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
kafka-console-producer --bootstrap-server kafka:9092 --topic content-events
> {"post_id":"test123","user_id":"user456",...}

# 检查 feed-service 是否消费
kubectl logs -f feed-service-xxx | grep "test123"
```

### 3. 性能测试

```bash
# 压测 content-events topic
kafka-producer-perf-test \
  --topic content-events \
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
- [x] Kafka 添加 content-events topic (6 partitions)
- [x] feed-service 移除 wait-for-content-service
- [ ] content-service 发布 PostCreated 事件
- [ ] content-service 发布 PostUpdated 事件
- [ ] content-service 发布 PostDeleted 事件
- [ ] feed-service 订阅 content-events
- [ ] feed-service 维护本地内容索引
- [ ] 测试事件流

### Phase 3: Media Events ✅
- [x] Kafka 添加 media-events topic (3 partitions)
- [x] media-service 移除 wait-for-content-service
- [ ] media-service 发布 MediaUploaded 事件
- [ ] content-service 订阅 media-events
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
