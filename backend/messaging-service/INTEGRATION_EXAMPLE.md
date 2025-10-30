# Push Notification Integration Example

如何在 messaging-service 的 main.rs 中集成推送通知系统。

## Step 1: 在 main.rs 中初始化推送提供者

```rust
use std::sync::Arc;
use services::push::ApnsPush;
use services::fcm::FcmPush;
use services::notification_queue::{PostgresNotificationQueue, NotificationQueue};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // ... 现有的初始化代码 ...

    // 初始化 APNs provider (iOS)
    let apns_provider = if let Some(ref apns_config) = config.apns {
        match ApnsPush::new(apns_config) {
            Ok(provider) => {
                info!("APNs provider initialized successfully");
                Some(Arc::new(provider))
            }
            Err(e) => {
                warn!("Failed to initialize APNs provider: {}", e);
                None
            }
        }
    } else {
        info!("APNs not configured, iOS push notifications disabled");
        None
    };

    // 初始化 FCM provider (Android)
    let fcm_provider = if let Some(ref fcm_config) = config.fcm {
        match FcmPush::new(fcm_config.api_key.clone()) {
            Ok(provider) => {
                info!("FCM provider initialized successfully");
                Some(Arc::new(provider))
            }
            Err(e) => {
                warn!("Failed to initialize FCM provider: {}", e);
                None
            }
        }
    } else {
        info!("FCM not configured, Android push notifications disabled");
        None
    };

    // 创建通知队列
    let notification_queue = Arc::new(PostgresNotificationQueue::new(
        Arc::new(db_pool.clone()),
        apns_provider,
        fcm_provider,
    ));

    // ... 继续其他初始化 ...
}
```

## Step 2: 启动后台队列处理器

在 main.rs 中添加后台任务：

```rust
// 启动通知队列处理器（每5秒处理一次）
let queue_processor = notification_queue.clone();
tokio::spawn(async move {
    use tokio::time::{interval, Duration};
    let mut ticker = interval(Duration::from_secs(5));

    info!("Starting notification queue processor");

    loop {
        ticker.tick().await;

        match queue_processor.process_pending().await {
            Ok(count) if count > 0 => {
                info!("Processed {} notifications", count);
            }
            Err(e) => {
                error!("Failed to process notification queue: {}", e);
            }
            _ => {}
        }
    }
});

info!("Notification queue processor started");
```

## Step 3: 在 WebSocket 消息处理中发送通知

在 `websocket/handlers.rs` 或相关消息处理逻辑中：

```rust
use services::notification_queue::{NotificationJob, NotificationQueue};

async fn handle_new_message(
    message: Message,
    notification_queue: Arc<dyn NotificationQueue>,
) -> Result<(), AppError> {
    // ... 保存消息到数据库 ...

    // 获取接收者的设备信息
    let devices = get_user_devices(message.receiver_id).await?;

    // 为每个设备创建通知任务
    for device in devices {
        let job = NotificationJob::new(
            device.token,
            device.platform, // "ios" 或 "android"
            format!("{} 给你发送了一条消息", message.sender_name),
            message.content_preview(),
            Some(device.unread_count),
        );

        // 加入队列（异步非阻塞）
        if let Err(e) = notification_queue.queue_notification(job).await {
            error!("Failed to queue notification: {}", e);
            // 不中断消息流程
        }
    }

    Ok(())
}
```

## Step 4: 在应用状态中共享队列

修改 `AppState` 结构体：

```rust
#[derive(Clone)]
pub struct AppState {
    pub db: Arc<PgPool>,
    pub redis: Arc<ConnectionManager>,
    // ... 其他字段 ...
    pub notification_queue: Arc<dyn NotificationQueue>,
}
```

在路由中使用：

```rust
async fn send_message_handler(
    State(state): State<AppState>,
    Json(payload): Json<SendMessageRequest>,
) -> Result<Json<MessageResponse>, AppError> {
    // ... 处理消息 ...

    // 发送推送通知
    let job = NotificationJob::new(
        payload.device_token,
        payload.platform,
        "新消息".to_string(),
        payload.message,
        Some(1),
    );

    state.notification_queue.queue_notification(job).await?;

    Ok(Json(response))
}
```

## Step 5: 添加通知状态查询端点

在 `routes/notifications.rs` 中：

```rust
use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use uuid::Uuid;

/// 查询通知状态
pub async fn get_notification_status(
    State(state): State<AppState>,
    Path(job_id): Path<Uuid>,
) -> Result<Json<NotificationJob>, AppError> {
    let job = state
        .notification_queue
        .get_status(job_id)
        .await?
        .ok_or(AppError::NotFound)?;

    Ok(Json(job))
}

/// 取消待发送的通知
pub async fn cancel_notification(
    State(state): State<AppState>,
    Path(job_id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    state.notification_queue.cancel_notification(job_id).await?;
    Ok(StatusCode::NO_CONTENT)
}
```

注册路由：

```rust
let notification_routes = Router::new()
    .route("/notifications/:job_id", get(get_notification_status))
    .route("/notifications/:job_id", delete(cancel_notification))
    .with_state(app_state.clone());

let app = Router::new()
    .merge(notification_routes)
    // ... 其他路由 ...
```

## Step 6: 运行数据库迁移

在部署前运行迁移：

```bash
cd backend/messaging-service
sqlx migrate run --database-url $DATABASE_URL
```

或者在 main.rs 启动时自动运行：

```rust
// 运行数据库迁移
sqlx::migrate!("../migrations")
    .run(&db_pool)
    .await
    .expect("Failed to run migrations");

info!("Database migrations completed");
```

## Step 7: 配置环境变量

在 `.env` 文件中添加：

```bash
# APNs 配置 (iOS)
APNS_CERTIFICATE_PATH=/path/to/apns_certificate.p12
APNS_CERTIFICATE_PASSPHRASE=your_cert_password
APNS_BUNDLE_ID=com.example.novasocial
APNS_IS_PRODUCTION=false  # 开发环境用 false，生产环境用 true

# FCM 配置 (Android)
FCM_API_KEY=your_fcm_server_key_here
```

## Step 8: 测试推送通知

### 单元测试

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_notification_queue_integration() {
        // 创建测试数据库
        let db_pool = setup_test_db().await;

        // 初始化队列（不配置真实的推送提供者）
        let queue = Arc::new(PostgresNotificationQueue::new(
            Arc::new(db_pool),
            None,
            None,
        ));

        // 创建测试通知
        let job = NotificationJob::new(
            "test_token_123".to_string(),
            "ios".to_string(),
            "Test Title".to_string(),
            "Test Body".to_string(),
            Some(1),
        );

        // 加入队列
        queue.queue_notification(job.clone()).await.unwrap();

        // 查询状态
        let status = queue.get_status(job.id).await.unwrap();
        assert!(status.is_some());
        assert_eq!(status.unwrap().status, "pending");
    }
}
```

### 集成测试

使用真实的设备 token 进行测试：

```bash
# 创建测试脚本
cat > test_push.sh << 'EOF'
#!/bin/bash

# iOS 测试
curl -X POST http://localhost:3000/api/test/push \
  -H "Content-Type: application/json" \
  -d '{
    "device_token": "YOUR_APNS_DEVICE_TOKEN",
    "platform": "ios",
    "title": "测试通知",
    "body": "这是一条测试推送",
    "badge": 1
  }'

# Android 测试
curl -X POST http://localhost:3000/api/test/push \
  -H "Content-Type: application/json" \
  -d '{
    "device_token": "YOUR_FCM_REGISTRATION_TOKEN",
    "platform": "android",
    "title": "测试通知",
    "body": "这是一条测试推送",
    "badge": 1
  }'
EOF

chmod +x test_push.sh
./test_push.sh
```

## 监控和日志

查看推送通知日志：

```bash
# 查看成功发送的通知
docker logs messaging-service | grep "notification sent successfully"

# 查看失败的通知
docker logs messaging-service | grep "Failed to send notification"

# 查看队列处理情况
docker logs messaging-service | grep "Processed .* notifications"
```

数据库查询：

```sql
-- 查看待发送的通知
SELECT * FROM notification_jobs WHERE status = 'pending';

-- 查看失败的通知
SELECT * FROM notification_jobs WHERE status = 'failed';

-- 统计各平台成功率
SELECT
    platform,
    COUNT(*) as total,
    SUM(CASE WHEN status = 'sent' THEN 1 ELSE 0 END) as sent,
    ROUND(100.0 * SUM(CASE WHEN status = 'sent' THEN 1 ELSE 0 END) / COUNT(*), 2) as success_rate
FROM notification_jobs
GROUP BY platform;
```

## 完整的 main.rs 示例

```rust
use axum::{routing::get, Router};
use services::{
    fcm::FcmPush,
    notification_queue::{NotificationQueue, PostgresNotificationQueue},
    push::ApnsPush,
};
use sqlx::postgres::PgPoolOptions;
use std::sync::Arc;
use tokio::time::{interval, Duration};
use tower_http::trace::TraceLayer;
use tracing::{error, info, warn};

mod config;
mod error;
mod routes;
mod services;
mod state;

use config::Config;
use state::AppState;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // 初始化日志
    tracing_subscriber::fmt::init();

    info!("Starting messaging-service...");

    // 加载配置
    let config = Config::from_env()?;

    // 数据库连接池
    let db_pool = PgPoolOptions::new()
        .max_connections(20)
        .connect(&config.database_url)
        .await?;

    info!("Database connected");

    // 运行迁移
    sqlx::migrate!("../migrations")
        .run(&db_pool)
        .await?;

    info!("Database migrations completed");

    // Redis 连接
    let redis_client = redis::Client::open(config.redis_url.as_str())?;
    let redis_conn = redis::aio::ConnectionManager::new(redis_client).await?;

    info!("Redis connected");

    // 初始化推送提供者
    let apns_provider = config.apns.as_ref().and_then(|cfg| {
        match ApnsPush::new(cfg) {
            Ok(provider) => {
                info!("APNs provider initialized");
                Some(Arc::new(provider))
            }
            Err(e) => {
                warn!("Failed to initialize APNs: {}", e);
                None
            }
        }
    });

    let fcm_provider = config.fcm.as_ref().and_then(|cfg| {
        match FcmPush::new(cfg.api_key.clone()) {
            Ok(provider) => {
                info!("FCM provider initialized");
                Some(Arc::new(provider))
            }
            Err(e) => {
                warn!("Failed to initialize FCM: {}", e);
                None
            }
        }
    });

    // 通知队列
    let notification_queue: Arc<dyn NotificationQueue> = Arc::new(PostgresNotificationQueue::new(
        Arc::new(db_pool.clone()),
        apns_provider,
        fcm_provider,
    ));

    info!("Notification queue initialized");

    // 应用状态
    let app_state = AppState {
        db: Arc::new(db_pool),
        redis: Arc::new(redis_conn),
        notification_queue: notification_queue.clone(),
    };

    // 启动通知队列处理器
    let queue_processor = notification_queue;
    tokio::spawn(async move {
        let mut ticker = interval(Duration::from_secs(5));
        info!("Notification queue processor started");

        loop {
            ticker.tick().await;
            match queue_processor.process_pending().await {
                Ok(count) if count > 0 => {
                    info!("Processed {} notifications", count);
                }
                Err(e) => {
                    error!("Failed to process notifications: {}", e);
                }
                _ => {}
            }
        }
    });

    // 路由
    let app = Router::new()
        .route("/health", get(|| async { "OK" }))
        .nest("/api", routes::api_routes())
        .with_state(app_state)
        .layer(TraceLayer::new_for_http());

    // 启动服务器
    let addr = format!("0.0.0.0:{}", config.port);
    let listener = tokio::net::TcpListener::bind(&addr).await?;

    info!("Server listening on {}", addr);

    axum::serve(listener, app).await?;

    Ok(())
}
```

## 性能优化建议

### 1. 批量处理优化

修改 `process_pending()` 使用并发发送：

```rust
use futures::future::join_all;

async fn process_pending_concurrent(&self) -> Result<usize, AppError> {
    let jobs = self.fetch_pending_jobs().await?;

    let tasks: Vec<_> = jobs.into_iter().map(|job| {
        let queue = self.clone();
        tokio::spawn(async move {
            match queue.send_with_provider(&job).await {
                Ok(_) => queue.mark_sent(job.id).await,
                Err(e) => queue.mark_failed(job.id, e.to_string()).await,
            }
        })
    }).collect();

    let results = join_all(tasks).await;
    Ok(results.into_iter().filter(|r| r.is_ok()).count())
}
```

### 2. 连接池调优

```rust
let db_pool = PgPoolOptions::new()
    .max_connections(50)  // 增加连接数
    .acquire_timeout(Duration::from_secs(5))
    .idle_timeout(Duration::from_secs(600))
    .connect(&config.database_url)
    .await?;
```

### 3. Redis 缓存设备信息

```rust
async fn get_device_with_cache(
    user_id: Uuid,
    redis: &ConnectionManager,
    db: &PgPool,
) -> Result<Vec<Device>, AppError> {
    let cache_key = format!("devices:{}", user_id);

    // 尝试从 Redis 获取
    if let Ok(cached) = redis.get::<_, String>(&cache_key).await {
        if let Ok(devices) = serde_json::from_str(&cached) {
            return Ok(devices);
        }
    }

    // 从数据库获取
    let devices = fetch_devices_from_db(user_id, db).await?;

    // 缓存到 Redis（TTL: 1小时）
    let _ = redis.set_ex(
        &cache_key,
        serde_json::to_string(&devices)?,
        3600,
    ).await;

    Ok(devices)
}
```

完成！现在你有一个完整的、生产级别的推送通知系统。
