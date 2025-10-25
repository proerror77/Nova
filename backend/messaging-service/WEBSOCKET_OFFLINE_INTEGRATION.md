# WebSocket 离线消息队列集成指南

## 概述

此文档描述了WebSocket处理程序如何与Redis Streams离线消息队列集成，以实现客户端离线时的消息恢复。

## 核心流程（7个步骤）

### 步骤1: 生成客户端ID并检索同步状态

当WebSocket连接建立时，处理程序生成一个唯一的客户端ID，并从Redis中检索该客户端的上一次同步状态。

```rust
let client_id = Uuid::new_v4();

let last_message_id = if let Ok(Some(sync_state)) = offline_queue::get_client_sync_state(
    &state.redis,
    params.user_id,
    client_id,
).await {
    sync_state.last_message_id.clone()
} else {
    // 新客户端，从头开始
    "0".to_string()
};
```

**关键点**:
- 每个连接都有唯一的客户端ID
- 客户端ID与用户ID一起使用确保多设备支持
- 如果没有之前的状态，使用"0"表示从头开始

### 步骤2: 获取并发送离线消息

WebSocket处理程序从Redis Streams中查询自上次同步以来的所有消息，并立即发送给客户端。

```rust
if let Ok(offline_messages) = offline_queue::get_messages_since(
    &state.redis,
    params.conversation_id,
    &last_message_id,
).await {
    for (_stream_id, fields) in offline_messages {
        if let Some(payload) = fields.get("payload") {
            let msg = Message::Text(payload.clone());
            if sender.send(msg).await.is_err() {
                return; // 连接已关闭
            }
        }
    }
}
```

**关键点**:
- XRANGE查询使用独占范围`(last_message_id`，避免重复
- 消息按照发送时间有序的顺序发送
- 如果连接在此期间断开，我们立即返回

### 步骤3: 注册到本地广播注册表

将连接注册到内存中的广播系统，用于接收实时消息。

```rust
let mut rx = state.registry.add_subscriber(params.conversation_id).await;
```

**关键点**:
- 这是一个本地通道，用于同一实例上的实时消息
- 不会捕获存储在Redis中的历史消息
- 与Redis Streams独立工作，提供低延迟

### 步骤4: 跟踪最后接收的消息ID

创建一个Arc<Mutex>来跟踪此连接接收的最新消息ID。

```rust
let last_received_id = Arc::new(Mutex::new(last_message_id.clone()));
```

**关键点**:
- 使用Arc允许在多个任务之间共享
- Mutex确保并发访问安全
- 初始化为前一个同步状态或"0"

### 步骤5: 启动定期同步任务

生成一个后台任务，每5秒更新客户端的同步状态。

```rust
let sync_task = {
    let redis = state.redis.clone();
    let user_id = params.user_id;
    let conversation_id = params.conversation_id;
    let last_id = Arc::clone(&last_received_id);

    tokio::spawn(async move {
        let mut interval = tokio::time::interval(
            std::time::Duration::from_secs(5)
        );
        loop {
            interval.tick().await;
            let current_id = last_id.lock().await.clone();
            let sync_state = ClientSyncState {
                client_id,
                user_id,
                conversation_id,
                last_message_id: current_id,
                last_sync_at: chrono::Utc::now().timestamp(),
            };
            let _ = offline_queue::update_client_sync_state(
                &redis,
                &sync_state
            ).await;
        }
    })
};
```

**关键点**:
- 5秒间隔平衡持久性和Redis负载
- 定期更新确保如果连接意外断开，状态仍然是最新的
- 由Arc<Mutex>保护，所以不会丢失并发更新

### 步骤6: 主消息循环 - 多路复用

使用`tokio::select!`同时处理传入的广播消息和来自客户端的消息。

```rust
loop {
    tokio::select! {
        // 处理传出的广播消息
        maybe = rx.recv() => {
            match maybe {
                Some(msg) => {
                    // 提取流ID并更新last_received_id
                    if let Message::Text(ref txt) = msg {
                        if let Ok(json) = serde_json::from_str::<serde_json::Value>(txt) {
                            if let Some(id) = json.get("stream_id").and_then(|v| v.as_str()) {
                                *last_received_id.lock().await = id.to_string();
                            }
                        }
                    }
                    if sender.send(msg).await.is_err() { break; }
                }
                None => break,
            }
        }

        // 处理传入的客户端消息
        incoming = receiver.next() => {
            match incoming {
                Some(Ok(Message::Text(txt))) => {
                    // 处理客户端事件（例如typing）
                    if let Ok(evt) = serde_json::from_str::<WsInboundEvent>(&txt) {
                        // 处理事件...
                    }
                }
                Some(Ok(Message::Ping(data))) => {
                    let _ = sender.send(Message::Pong(data)).await;
                }
                Some(Ok(Message::Close(_))) | None => break,
                _ => {}
            }
        }
    }
}
```

**关键点**:
- 同时处理入站和出站消息，避免死锁
- 实时消息立即更新`last_received_id`
- 断开连接会立即跳出循环

### 步骤7: 清理和最终状态保存

当连接关闭时，保存最终状态并取消同步任务。

```rust
// 保存最终同步状态在断开连接时
let final_id = last_received_id.lock().await.clone();
let final_state = ClientSyncState {
    client_id,
    user_id: params.user_id,
    conversation_id: params.conversation_id,
    last_message_id: final_id,
    last_sync_at: chrono::Utc::now().timestamp(),
};
let _ = offline_queue::update_client_sync_state(&state.redis, &final_state).await;

// 取消同步任务
sync_task.abort();
```

**关键点**:
- 最终状态保存确保下次连接时可以从正确的位置恢复
- abort()是安全的，不会导致资源泄漏
- 30天的TTL确保状态不会无限期保留

## 数据流图

```
┌─ Client Connects ──────────────────────────────────────┐
│                                                          │
├─ Step 1: Retrieve Sync State ─────────────────┐        │
│         (last_message_id)                     │        │
│                                               ↓        │
├─ Step 2: Fetch Offline Messages ────→ XRANGE from      │
│         Send to Client                       Redis      │
│                                               ↑        │
├─ Step 3: Register to Broadcast ─────────────┤        │
│         (local in-memory channel)            │        │
│                                               │        │
├─ Step 4: Track last_received_id ────────────┤        │
│         (Arc<Mutex<String>>)                 │        │
│                                               │        │
├─ Step 5: Start Sync Task ──────────────────┐ │        │
│         (every 5 sec) ──────────────────────┼─┼─────→ Redis
│                                              │ │      set_ex
│                                              │ │
│ ┌──────────── Step 6: Main Loop ──────────┐ │ │
│ │                                          │ │ │
│ ├─ Incoming Broadcast ──────────┬─────────┼─┤─┼─────→ Broadcast
│ │                                ↓         │ │ │       Registry
│ │                         Update last_id  │ │ │
│ │                                          │ │ │
│ ├─ Incoming Client Events ────────────────┼─┼─┼──→ Handle/Broadcast
│ │                                          │ │ │
│ └──────────────────────────────────────────┘ │ │
│                                               │ │
├─ Client Disconnects ──────────────────────────┤ │
│                                               │ │
├─ Step 7: Save Final State ──────────────────┼─┼─→ Redis
│         Cancel Sync Task                    │ │
│                                             └─┘
└──────────────────────────────────────────────┘
```

## 时间线示例

### 场景: 客户端离线恢复

```
T=0s:   Client A connects
        └─ Retrieves last_message_id = "1500-0" (from previous session)
        └─ Fetches and receives messages from "1500-0" onward (2 new messages)
        └─ Registers for real-time messages

T=1s:   New message arrives from other user
        └─ Broadcast delivers to Client A
        └─ last_received_id updated to "1502-0"

T=5s:   First sync task tick
        └─ Persists last_message_id = "1502-0" to Redis

T=10s:  Client A internet drops (connection terminates unexpectedly)
        └─ Cleanup runs
        └─ Final state saved: last_message_id = "1502-0"
        └─ Sync task cancelled

T=15s:  New message arrives while Client A is offline
        └─ Published to stream:conversation:{id}
        └─ Stored in Redis with ID "1503-0"

T=20s:  Client A reconnects
        └─ New client_id generated
        └─ Retrieves sync state: last_message_id = "1502-0"
        └─ XRANGE queries from "(1502-0" onward
        └─ Receives the message from T=15s

T=25s:  Second sync task tick (on new connection)
        └─ Updates last_message_id = "1503-0"
```

## 关键设计决策

### 为什么使用Arc<Mutex>而不是Channel?
- **轻量级**: 避免额外的通道开销
- **实时**: 同步任务可以立即看到最新值
- **简单**: 不需要复杂的channel逻辑

### 为什么5秒同步间隔?
- **平衡**: 足够频繁确保持久性，但不会过度负载Redis
- **可配置**: 可以通过环境变量调整
- **重要**: 系统启动时立即同步（步骤0）

### 为什么分离实时广播和Redis Streams?
- **低延迟**: 本地内存通道提供毫秒级消息传递
- **备份**: Redis Streams为离线恢复提供持久性
- **独立失败**: 若Redis故障，实时消息仍继续工作

### 为什么是Stream Entry ID而不是序列号?
- **全局顺序**: Redis生成的ID保证全局顺序
- **时间戳**: ID编码时间信息
- **持久**: ID在Redis中永久存在

## 错误处理

### 网络中断期间的消息丢失
**解决方案**: 消息在Redis Streams中保留30天（可配置TTL）

### 并发访问last_received_id
**解决方案**: 使用Mutex保护，所有更新都是原子的

### 同步任务失败
**解决方案**: 结果被丢弃(_表示)，连接继续工作。在下次同步时重试。

### Redis连接故障
**解决方案**: 返回结果被忽略。本地广播继续工作。客户端在重新连接时获得同步状态。

## 监控和调试

### 关键指标
1. **同步延迟**: 消息接收到Redis持久化之间的时间
2. **恢复延迟**: 离线消息发送到已连接客户端的时间
3. **状态失效率**: 同步失败的百分比
4. **离线消息队列大小**: Redis中待恢复消息的字节数

### 调试命令

```bash
# 检查特定客户端的同步状态
redis-cli GET "client:sync:{user_id}:{client_id}"

# 查看特定会话的消息流
redis-cli XRANGE "stream:conversation:{conversation_id}" - + COUNT 10

# 监视会话的消费者组进度
redis-cli XINFO GROUPS "stream:conversation:{conversation_id}"

# 查找待ACK消息
redis-cli XPENDING "stream:conversation:{conversation_id}" "group_name"
```

## 性能特征

| 操作 | 时间复杂度 | 空间复杂度 | 注释 |
|------|----------|----------|------|
| 检索同步状态 | O(1) | O(1) | Redis GET |
| 获取离线消息 | O(k) | O(k) | k = 消息数，XRANGE有限范围 |
| 广播消息 | O(n) | O(1) | n = 连接数，内存通道 |
| 更新同步状态 | O(1) | O(1) | Redis SET_EX |

## 未来改进

### 短期
1. 添加metrics导出（Prometheus）
2. 实现可配置的同步间隔
3. 添加同步状态数据库备份

### 中期
1. 消费者组支持（用于负载均衡）
2. 消息压缩（针对大型会话）
3. 自适应TTL（基于消息速率）

### 长期
1. 分布式会话管理（跨实例同步）
2. 消息加密（E2E）
3. 优先级队列（重要消息优先传递）

## 测试覆盖

集成测试位于 `tests/websocket_offline_recovery_test.rs`：

1. **test_offline_message_recovery_basic_flow** - 完整的离线/在线周期
2. **test_offline_message_recovery_with_no_previous_state** - 首次连接场景
3. **test_multiple_clients_same_conversation_independent_recovery** - 多设备支持
4. **test_client_sync_state_persistence_and_ttl** - 状态持久性和生命周期

运行测试（需要Redis在运行）:
```bash
cargo test --test websocket_offline_recovery_test
```

## 相关文件

- `src/websocket/handlers.rs` - WebSocket处理程序实现
- `src/services/offline_queue.rs` - 离线队列操作
- `src/websocket/streams.rs` - Redis Streams核心逻辑
- `REDIS_STREAMS_MIGRATION.md` - Streams架构详解
