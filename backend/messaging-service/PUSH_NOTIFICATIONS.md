# Push Notifications System

完整的推送通知系统实现，支持 APNs (iOS) 和 FCM (Android)。

## 架构概览

```
┌─────────────┐
│  WebSocket  │
│   Events    │
└──────┬──────┘
       │
       v
┌─────────────────────────────────────┐
│     Notification Queue (PostgreSQL) │
│  ┌──────────────────────────────┐   │
│  │   notification_jobs table    │   │
│  └──────────────────────────────┘   │
└──────┬──────────────────────────────┘
       │
       v
┌──────────────────┐
│  Queue Processor │
│  (Background Job)│
└──────┬───────────┘
       │
       ├─────────────┐
       v             v
┌──────────┐  ┌──────────┐
│  APNs    │  │   FCM    │
│ Provider │  │ Provider │
└──────────┘  └──────────┘
```

## 组件说明

### 1. PushProvider Trait

统一的推送通知接口，抽象了平台差异：

```rust
#[async_trait]
pub trait PushProvider: Send + Sync {
    async fn send(
        &self,
        device_token: String,
        title: String,
        body: String,
        badge: Option<u32>,
    ) -> Result<(), AppError>;
}
```

### 2. APNs Provider (ApnsPush)

- 使用 `apns2` 库
- 支持生产和开发环境
- 证书认证
- 高优先级推送

### 3. FCM Provider (FcmPush)

- 使用 `fcm` v0.9 库
- API Key 认证
- 支持通知和数据消息

### 4. Notification Queue (PostgresNotificationQueue)

持久化通知队列，特性：
- 自动重试机制（最多3次）
- 失败追踪和错误记录
- 批量处理（每次最多100条）
- 状态管理（pending/sent/failed）

## 数据库表结构

```sql
CREATE TABLE notification_jobs (
    id UUID PRIMARY KEY,
    device_token TEXT NOT NULL,
    platform VARCHAR(20) NOT NULL CHECK (platform IN ('ios', 'android')),
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    badge INTEGER,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    retry_count INTEGER NOT NULL DEFAULT 0,
    max_retries INTEGER NOT NULL DEFAULT 3,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sent_at TIMESTAMPTZ,
    last_error TEXT
);
```

## 环境变量配置

### APNs (iOS)

```bash
# APNs 证书路径 (.p12 文件)
APNS_CERTIFICATE_PATH=/path/to/certificate.p12

# 证书密码（可选）
APNS_CERTIFICATE_PASSPHRASE=your_passphrase

# App Bundle ID
APNS_BUNDLE_ID=com.example.app

# 是否使用生产环境（默认: false）
APNS_IS_PRODUCTION=true
```

### FCM (Android)

```bash
# FCM Server API Key (Legacy) 或 Service Account Key
FCM_API_KEY=your_fcm_api_key
```

## 使用示例

### 初始化推送提供者

```rust
use std::sync::Arc;
use sqlx::PgPool;

// 初始化 APNs
let apns_provider = if let Some(apns_config) = &config.apns {
    Some(Arc::new(ApnsPush::new(apns_config)?))
} else {
    None
};

// 初始化 FCM
let fcm_provider = if config.fcm.is_some() {
    Some(Arc::new(FcmPush::new(
        config.fcm.as_ref().unwrap().api_key.clone()
    )?))
} else {
    None
};

// 创建通知队列
let notification_queue = Arc::new(PostgresNotificationQueue::new(
    Arc::new(db_pool),
    apns_provider,
    fcm_provider,
));
```

### 发送通知

```rust
use services::notification_queue::{NotificationJob, NotificationQueue};

// 创建通知任务
let job = NotificationJob::new(
    device_token,
    "ios".to_string(), // 或 "android"
    "新消息".to_string(),
    "你有一条来自 Alice 的新消息".to_string(),
    Some(1), // 角标数
);

// 加入队列
notification_queue.queue_notification(job).await?;
```

### 后台处理器

在 `main.rs` 中启动后台任务处理器：

```rust
use tokio::time::{interval, Duration};

// 启动通知队列处理器
let queue_clone = notification_queue.clone();
tokio::spawn(async move {
    let mut ticker = interval(Duration::from_secs(5));
    loop {
        ticker.tick().await;
        if let Err(e) = queue_clone.process_pending().await {
            error!("Failed to process notification queue: {}", e);
        }
    }
});
```

### 查询通知状态

```rust
// 通过 Job ID 查询状态
let status = notification_queue.get_status(job_id).await?;

if let Some(job) = status {
    match job.status.as_str() {
        "pending" => println!("通知待发送"),
        "sent" => println!("通知已发送: {:?}", job.sent_at),
        "failed" => println!("通知发送失败: {:?}", job.last_error),
        _ => {}
    }
}
```

### 取消通知

```rust
// 取消待发送的通知
notification_queue.cancel_notification(job_id).await?;
```

## 重试机制

通知发送失败时会自动重试：

1. **最大重试次数**: 3次
2. **重试条件**: `retry_count < max_retries` 且 `status = 'pending'`
3. **失败处理**:
   - 记录错误信息到 `last_error`
   - 增加 `retry_count`
   - 达到最大次数后标记为 `'failed'`

## 监控和调试

### 日志

系统会记录以下日志：

```rust
// 成功
info!("Queued notification job {} for {} device", job.id, job.platform);
info!("Successfully sent notification job {}", job.id);

// 失败
warn!("Failed to send notification job {} (attempt {}/{}): {}", ...);
error!("Failed to mark job {} as sent: {}", ...);
```

### 查询失败的通知

```sql
-- 查看所有失败的通知
SELECT id, device_token, platform, title, retry_count, last_error, created_at
FROM notification_jobs
WHERE status = 'failed'
ORDER BY created_at DESC;

-- 统计平台成功率
SELECT
    platform,
    COUNT(*) as total,
    SUM(CASE WHEN status = 'sent' THEN 1 ELSE 0 END) as sent,
    SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failed
FROM notification_jobs
GROUP BY platform;
```

## 性能优化建议

### 1. 批量处理

当前每次处理最多100条待发送通知，可根据实际情况调整：

```rust
// 在 notification_queue.rs 中修改 LIMIT
LIMIT 100  -- 调整此值
```

### 2. 并发发送

修改 `process_pending()` 使用 `futures::future::join_all()` 并发发送：

```rust
use futures::future::join_all;

let send_tasks = jobs.into_iter().map(|job| {
    let queue = self.clone();
    async move {
        // 发送逻辑
    }
});

join_all(send_tasks).await;
```

### 3. 定时任务频率

根据业务需求调整后台处理器频率：

```rust
let mut ticker = interval(Duration::from_secs(5)); // 5秒处理一次
```

### 4. 数据库索引

已创建的索引：
- `idx_notification_jobs_status_retry`: 优化待发送通知查询
- `idx_notification_jobs_created_at`: 优化时间范围查询
- `idx_notification_jobs_device_token`: 优化设备查询

### 5. 归档旧数据

定期清理已成功发送的旧通知：

```sql
-- 删除30天前已发送的通知
DELETE FROM notification_jobs
WHERE status = 'sent'
  AND sent_at < NOW() - INTERVAL '30 days';
```

## 安全注意事项

1. **设备 Token 保护**
   - 日志中只记录 token 的前8个字符
   - 避免在日志中暴露完整 token

2. **API Key 安全**
   - 使用环境变量存储
   - 切勿提交到版本控制
   - 定期轮换 API Key

3. **证书管理**
   - APNs 证书使用密码保护
   - 限制证书文件访问权限
   - 证书过期前及时更新

## 测试

### 单元测试

```bash
cargo test --package messaging-service --lib services::notification_queue
cargo test --package messaging-service --lib services::fcm
cargo test --package messaging-service --lib services::push
```

### 集成测试

创建集成测试验证完整流程：

```rust
#[tokio::test]
async fn test_notification_flow() {
    // 1. 创建测试数据库
    // 2. 初始化队列
    // 3. 发送测试通知
    // 4. 验证状态变化
}
```

## 故障排查

### APNs 常见问题

1. **证书错误**
   ```
   Error: failed to initialize APNs client: invalid certificate
   ```
   解决：检查证书路径和密码是否正确

2. **设备 Token 无效**
   ```
   Error: APNs send failed: BadDeviceToken
   ```
   解决：验证设备 token 格式（64个十六进制字符）

### FCM 常见问题

1. **API Key 无效**
   ```
   Error: FCM_API_KEY not set
   ```
   解决：设置 FCM_API_KEY 环境变量

2. **设备未注册**
   ```
   Error: NotRegistered
   ```
   解决：从数据库中移除无效的设备 token

## 扩展建议

### 1. 支持更多平台

添加新的 PushProvider 实现：
- Web Push (浏览器)
- HMS (华为)
- JPUSH (极光推送)

### 2. 消息模板

实现消息模板系统，支持多语言和动态内容：

```rust
pub struct NotificationTemplate {
    pub id: String,
    pub title_template: String,
    pub body_template: String,
}
```

### 3. 用户偏好设置

允许用户配置通知偏好：
- 免打扰时段
- 消息类型过滤
- 通知声音选择

### 4. 统计和分析

添加通知送达率、打开率等指标：

```rust
pub struct NotificationMetrics {
    pub total_sent: u64,
    pub total_failed: u64,
    pub avg_delivery_time: Duration,
    pub platform_breakdown: HashMap<String, u64>,
}
```

## 参考资料

- [APNs Documentation](https://developer.apple.com/documentation/usernotifications)
- [FCM Documentation](https://firebase.google.com/docs/cloud-messaging)
- [apns2 Crate](https://docs.rs/apns2/)
- [fcm Crate](https://docs.rs/fcm/)
