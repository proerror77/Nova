# Nova Messaging System - 优先级修复清单

## 🔴 CRITICAL (必须在合并前修复)

### 1. WebSocket JWT验证绕过 [CRITICAL-1]
**文件:** `backend/messaging-service/src/websocket/handlers.rs:31-35`
**当前代码:**
```rust
if let Some(t) = token {
    if verify_jwt(&t).await.is_err() {
        return axum::http::StatusCode::UNAUTHORIZED.into_response();
    }
} // 如果无token则允许!
```

**修复方案:**
```rust
// 始终强制验证
let token = token_from_query.or(token_from_header)
    .ok_or(AppError::Unauthorized)?;
let _claims = verify_jwt(&token).await?;  // Fail if invalid
```

**验证:** 尝试不带token连接WS,应返回401

---

### 2. 权限检查故障开启 [CRITICAL-B]
**文件:** `backend/messaging-service/src/websocket/handlers.rs:45`
**当前代码:**
```rust
if !ConversationService::is_member(&state.db, params.conversation_id, params.user_id)
    .await
    .unwrap_or(false) {  // ❌ DB失败 = 允许访问
    // Close connection
}
```

**修复方案:**
```rust
let is_member = ConversationService::is_member(&state.db, params.conversation_id, params.user_id)
    .await
    .map_err(|_| {
        tracing::error!("DB error checking membership");
        AppError::Internal
    })?;

if !is_member {
    return;  // Close connection
}
```

---

### 3. LocalStorage纯文本泄露 [HIGH-D]
**文件:** `frontend/src/services/offlineQueue/Queue.ts`

**修复方案:** 添加加密层
```typescript
import { encryptData, decryptData } from '../encryption/client';

export class OfflineQueue {
  enqueue(item: QueuedMessage) {
    const items = load();
    if (!items.find((i) => i.idempotencyKey === item.idempotencyKey)) {
      items.push(item);
      // 加密整个列表
      const encrypted = encryptData(JSON.stringify(items), userKey);
      save(encrypted);
    }
  }

  drain(): QueuedMessage[] {
    const encrypted = localStorage.getItem(KEY);
    if (!encrypted) return [];
    
    try {
      const decrypted = decryptData(encrypted, userKey);
      const items = JSON.parse(decrypted);
      localStorage.removeItem(KEY);
      return items;
    } catch {
      // 无效的解密,清空
      localStorage.removeItem(KEY);
      return [];
    }
  }
}
```

---

### 4. 消息未序列化安全 [CRITICAL-2]
**文件:** `backend/messaging-service/src/websocket/handlers.rs:152`

**当前:**
```rust
let out_txt = serde_json::to_string(&out).unwrap();
```

**修复:**
```rust
let out_txt = match serde_json::to_string(&out) {
    Ok(s) => s,
    Err(e) => {
        tracing::error!("typing event serialization failed: {}", e);
        return; // 跳过此消息,不要panic
    }
};
```

---

## 🟠 HIGH (第一个冲刺内完成)

### 5. 离线恢复竞态条件 [RACE-1]
**文件:** `backend/messaging-service/src/websocket/handlers.rs:72-89`

**问题:** 恢复→注册间隙中的消息丢失

**修复方案 - 原子化恢复:**
```rust
// Step 1: 注册广播接收器FIRST
let mut rx = state.registry.add_subscriber(params.conversation_id).await;

// Step 2: 获取上次已看ID
let last_seen_id = ... // 从Redis获取

// Step 3: 获取并发送离线消息(已安全,因为已注册)
if let Ok(offline_messages) = offline_queue::get_messages_since(...) {
    for (_stream_id, fields) in offline_messages {
        if let Some(payload) = fields.get("payload") {
            sender.send(Message::Text(payload.clone())).await?;
            // 更新tracking
            if let Ok(json) = serde_json::from_str::<serde_json::Value>(payload) {
                if let Some(id) = json.get("stream_id").and_then(|v| v.as_str()) {
                    *last_received_id.lock().await = id.to_string();
                }
            }
        }
    }
}

// Step 4: 现在安全接收实时消息(已经注册!)
loop {
    tokio::select! {
        maybe = rx.recv() => {
            // 处理实时消息
        }
        incoming = receiver.next() => {
            // 处理客户端消息
        }
    }
}
```

---

### 6. 离线队列Never被排空 [BUG-1]
**文件:** `frontend/src/stores/messagingStore.ts`

**修复方案:** 添加排空逻辑
```typescript
// 在connectWs时,连接成功后排空队列
connectWs: (conversationId: string, userId: string) => {
    const client = createWebSocketClient(url, {
        onOpen: () => {
            // 连接成功,排空离线队列
            const queued = queue.drain();
            
            for (const item of queued) {
                // 重新尝试发送
                get().sendMessage(item.conversationId, item.userId, item.plaintext)
                    .catch(err => {
                        console.error('Failed to resend queued message:', err);
                        // 如果失败,重新入队
                        queue.enqueue(item);
                    });
            }
        },
        // ... 其他handlers
    });
}
```

---

### 7. Stream ID解析逻辑脆弱 [HIGH-3]
**文件:** `backend/messaging-service/src/websocket/handlers.rs:131-135`

**问题:** 假设所有消息都有stream_id,但Typing事件没有

**修复:**
```rust
// 将stream_id添加到所有事件
// 后端: routes/messages.rs
serde_json::json!({
    "type": "message",
    "stream_id": format!("{}", msg_id),  // ✅ 添加
    "conversation_id": conversation_id,
    "message": {...}
})

// 前端: handlers.rs
if let Message::Text(ref txt) = msg {
    if let Ok(json) = serde_json::from_str::<serde_json::Value>(txt) {
        if let Some(stream_id) = json.get("stream_id").and_then(|v| v.as_str()) {
            *last_received_id.lock().await = stream_id.to_string();
        }
    }
}
```

---

### 8. 无Redis Stream Trimming [HIGH-6]
**文件:** 需要新建 `backend/messaging-service/src/tasks/stream_trim.rs`

**添加后台任务:**
```rust
pub async fn trim_old_streams(redis: &Client) -> redis::RedisResult<()> {
    let mut conn = redis.get_multiplexed_async_connection().await?;
    
    // 删除超过7天的消息
    let cutoff = SystemTime::now() - Duration::from_secs(7 * 24 * 60 * 60);
    let cutoff_ms = cutoff.duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64;

    // 获取所有conversation streams
    let pattern = "stream:conversation:*";
    let keys: Vec<String> = conn.keys(pattern).await?;
    
    for key in keys {
        // XTRIM key MINID 0 [cutoff_ms]
        let _: () = redis::cmd("XTRIM")
            .arg(&key)
            .arg("MINID")
            .arg("~")  // 近似trimming
            .arg(cutoff_ms)
            .query_async(&mut conn)
            .await?;
    }
    
    Ok(())
}

// main.rs中每小时运行一次
tokio::spawn(async {
    let mut interval = tokio::time::interval(Duration::from_secs(3600));
    loop {
        interval.tick().await;
        if let Err(e) = trim_old_streams(&redis).await {
            tracing::warn!("stream trimming failed: {}", e);
        }
    }
});
```

---

### 9. 任务清理不完整 [MEDIUM-4]
**文件:** `backend/messaging-service/src/websocket/handlers.rs:181`

**修复:**
```rust
// 保存JoinHandle
let sync_task = tokio::spawn(...);

// ... WebSocket循环

// 断开连接时:
sync_task.abort();
// 可选: 等待确保最后状态被保存
let _timeout = tokio::time::timeout(
    Duration::from_secs(1),
    sync_task
).await;
```

---

### 10. 消息搜索完整性 [MEDIUM-7]
**文件:** `backend/messaging-service/src/services/message_service.rs:169-205`

**问题:** search_messages依赖未加密的search_text,但主消息已加密

**修复方案:** 确保搜索端点有明确约束
```rust
pub async fn search_messages(
    db: &Pool<Postgres>,
    conversation_id: Uuid,
    query: &str,
    limit: i64,
) -> Result<Vec<MessageDto>, AppError> {
    // 验证conversation已启用搜索
    let search_enabled: bool = sqlx::query_scalar(
        "SELECT search_enabled FROM conversations WHERE id = $1"
    )
    .bind(conversation_id)
    .fetch_one(db)
    .await?;
    
    if !search_enabled {
        return Err(AppError::Forbidden);  // 搜索已禁用
    }
    
    // 执行搜索(前提是clients已选择共享plaintext)
    // ...
}
```

---

## 🟡 MEDIUM (第二个冲刺)

### 11. 添加分页到消息历史
**文件:** `backend/messaging-service/src/routes/messages.rs:67-83`

**当前:** `LIMIT 200` 固定
**修复:** 支持cursor分页
```rust
#[derive(Deserialize)]
pub struct GetHistoryQuery {
    pub before_id: Option<Uuid>,  // 分页游标
    pub limit: Option<i64>,
}

// SELECT ... WHERE conversation_id = $1 
// AND (before_id IS NULL OR sequence_number < (
//     SELECT sequence_number FROM messages WHERE id = before_id
// ))
// ORDER BY sequence_number DESC
// LIMIT $2
```

---

### 12. 消息编辑/删除UI
**前端:** 添加按钮到MessageThread.tsx
```typescript
{messages.map((m) => (
  <div key={m.id} style={{ display: 'flex', justifyContent: 'space-between' }}>
    <div>
      <small>#{m.sequence_number}</small> {m.sender_id}: {m.preview}
    </div>
    {m.sender_id === userId && (
      <div>
        <button onClick={() => editMessage(m.id)}>✏️</button>
        <button onClick={() => deleteMessage(m.id)}>🗑️</button>
      </div>
    )}
  </div>
))}
```

---

### 13. WebSocket单元测试
**新文件:** `backend/messaging-service/tests/unit/test_ws_handlers.rs`

```rust
#[tokio::test]
async fn test_ws_rejects_invalid_token() {
    // 创建test server
    // 发送无效token → 期望401
}

#[tokio::test]
async fn test_ws_allows_valid_token() {
    // 创建test server
    // 发送有效token → 期望升级到WS
}

#[tokio::test]
async fn test_offline_message_recovery() {
    // 模拟: 消息→客户端断开→重连
    // 验证: 重连后收到之前的消息
}

#[tokio::test]
async fn test_typing_event_broadcast() {
    // 两个客户端连接
    // Client 1发送typing → Client 2应接收
}

#[tokio::test]
async fn test_concurrent_message_delivery() {
    // 3个客户端,100条并发消息
    // 验证: 顺序,无重复,无丢失
}

#[tokio::test]
async fn test_connection_cleanup() {
    // 连接→断开
    // 验证: 清理内存,停止同步任务
}
```

---

### 14. 添加Metrics
**新文件:** `backend/messaging-service/src/metrics/mod.rs`

```rust
use prometheus::{Counter, Gauge, Histogram};
use lazy_static::lazy_static;

lazy_static! {
    pub static ref ACTIVE_CONNECTIONS: Gauge = 
        Gauge::new("ws_active_connections", "Active WebSocket connections").unwrap();
    
    pub static ref MESSAGES_SENT: Counter = 
        Counter::new("messages_sent_total", "Total messages sent").unwrap();
    
    pub static ref MESSAGE_LATENCY: Histogram = 
        Histogram::new("message_latency_seconds", "Message delivery latency").unwrap();
    
    pub static ref OFFLINE_QUEUE_SIZE: Gauge = 
        Gauge::new("offline_queue_size", "Size of offline message queue").unwrap();
}

// 在handlers.rs中使用:
ACTIVE_CONNECTIONS.inc();  // 连接时
MESSAGES_SENT.inc();        // 消息时
MESSAGE_LATENCY.observe(duration_secs);
ACTIVE_CONNECTIONS.dec();   // 断开时
```

---

## 代码质量改进(可选,不阻止合并)

### 15. 添加消息队列大小限制
```typescript
// EnhancedWebSocketClient.ts
class MessageQueue {
  private maxSize = 100;
  private maxAgeMs = 5 * 60 * 1000;  // 5分钟

  enqueue(type: string, payload: any): void {
    const now = Date.now();
    
    // 移除过期消息
    this.queue = this.queue.filter(msg => now - msg.timestamp < this.maxAgeMs);
    
    // 检查大小限制
    if (this.queue.length >= this.maxSize) {
      console.warn('[WebSocket] Message queue full, dropping oldest');
      this.queue.shift();
    }
    
    this.queue.push({ type, payload, timestamp: now, attempts: 0 });
  }
}
```

---

## 验证检查表

完成每项修复后,运行:

```bash
# 1. 启动所有依赖
docker-compose up -d postgres redis

# 2. 设置环境
export DATABASE_URL="postgres://..."
export JWT_SECRET="test_secret"
export SECRETBOX_KEY_B64="..."

# 3. 运行后端测试
cd backend/messaging-service
cargo test --lib
cargo test --test '*'

# 4. 启动前端开发服务器
cd frontend
npm run dev

# 5. 手动测试
# - 无token连接WS → 应拒绝
# - 有效token连接 → 应成功
# - 发送消息 → 应通过Pub/Sub广播
# - 断开→重连 → 应恢复离线消息
# - 查看浏览器localStorage → 应是加密的(16进制)
```

---

## 预期合并PR说明

```markdown
## Summary
Fixes critical security and reliability issues in messaging system:

- [x] Enforce JWT validation on WebSocket connections
- [x] Fix fail-open security in permission checks
- [x] Encrypt offline messages in localStorage
- [x] Implement offline queue drain/retry
- [x] Fix offline recovery race condition
- [x] Add Stream ID to all WebSocket events
- [x] Implement Redis stream trimming
- [x] Add WebSocket handler unit tests
- [x] Add Prometheus metrics

## Security Impact
- Closes authentication bypass (CVE-like)
- Closes privilege escalation via DB failure
- Protects sensitive messages in transit

## Performance Impact
- Metrics enable production monitoring
- Stream trimming prevents memory bloat
- Message queue size limits prevent OOM

## Testing
- [ ] Local integration tests pass
- [ ] WebSocket connection flows verified
- [ ] Offline recovery tested
- [ ] Encryption/decryption verified
```

