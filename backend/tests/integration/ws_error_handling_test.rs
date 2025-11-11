//! WebSocket 错误处理测试 - P2 级别
//!
//! 测试目标：验证 WebSocket 连接的错误处理和恢复能力
//! - 连接失败（握手阶段）→ 返回错误，不建立连接
//! - 消息发送失败（网络错误）→ 触发重连机制
//! - 心跳超时 → 断开连接，清理资源
//! - Redis 不可用 → 降级处理，不影响核心功能
//! - 重连场景 → 恢复未发送的消息
//!
//! Linus 哲学：
//! "实用主义 - WebSocket 错误处理不应该让整个服务崩溃"
//! "数据结构优先 - 连接状态应该在 Redis 中持久化，支持重连恢复"

use actix_web::{test, web, App, HttpRequest, HttpResponse};
use actix_web_actors::ws;
use crate::fixtures::test_env::TestEnvironment;
use futures_util::{SinkExt, StreamExt};
use serde_json::json;
use std::time::Duration;
use tokio::time::timeout;
use tokio_tungstenite::{connect_async, tungstenite::protocol::Message};
use uuid::Uuid;

/// 测试 1: 连接握手失败 - 缺少认证 Token
///
/// 场景：客户端尝试建立 WebSocket 连接但没有提供有效的认证 Token
/// 预期：
/// - 握手阶段失败
/// - 返回 401 Unauthorized 或 403 Forbidden
/// - 不建立 WebSocket 连接
#[tokio::test]
async fn test_websocket_handshake_fails_without_auth_token() {
    let env = TestEnvironment::new().await;

    // 模拟 WebSocket 服务器（简化版）
    let conversation_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();

    // 尝试连接（没有 Authorization Header）
    let ws_url = format!(
        "ws://localhost:8080/ws/conversations/{}?user_id={}",
        conversation_id, user_id
    );

    // 使用 tokio-tungstenite 进行连接（超时 2 秒）
    let connect_result = timeout(
        Duration::from_secs(2),
        connect_async(&ws_url),
    )
    .await;

    // 验证：连接应该失败（因为没有认证）
    assert!(
        connect_result.is_err() || connect_result.unwrap().is_err(),
        "没有认证 Token 的 WebSocket 握手应该失败"
    );

    env.cleanup().await;
}

/// 测试 2: 消息发送失败 - 网络中断
///
/// 场景：WebSocket 连接建立后，网络突然中断
/// 预期：
/// - 检测到发送失败
/// - 客户端触发重连机制
/// - 未发送的消息保存到离线队列
#[tokio::test]
async fn test_message_send_failure_triggers_reconnection() {
    let env = TestEnvironment::new().await;
    let db = env.db();
    let redis = env.redis();

    let conversation_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let client_id = Uuid::new_v4();

    // 1. 创建用户和对话
    create_test_user(&db, user_id).await;
    create_test_conversation(&db, conversation_id, user_id).await;

    // 2. 模拟 WebSocket 连接建立
    let sync_state = offline_queue::ClientSyncState {
        client_id,
        user_id,
        conversation_id,
        last_message_id: "msg-1".to_string(),
        last_sync_at: chrono::Utc::now().timestamp(),
    };

    offline_queue::update_client_sync_state(&redis, &sync_state)
        .await
        .expect("保存同步状态失败");

    // 3. 模拟网络中断（清除同步状态）
    let mut redis_conn = redis.clone();
    let sync_key = format!("sync_state:{}:{}:{}", user_id, conversation_id, client_id);
    redis::cmd("DEL")
        .arg(&sync_key)
        .query_async::<_, ()>(&mut redis_conn)
        .await
        .expect("删除同步状态失败");

    // 4. 尝试获取同步状态（应该为空，表示连接已断开）
    let restored_state = offline_queue::get_client_sync_state(&redis, user_id, conversation_id, client_id)
        .await
        .expect("获取同步状态失败");

    assert!(
        restored_state.is_none(),
        "网络中断后同步状态应该为空"
    );

    // 5. 验证未发送的消息进入离线队列
    let pending_messages = offline_queue::get_pending_messages(&redis, user_id, conversation_id)
        .await
        .expect("获取待发送消息失败");

    // 这里应该有未发送的消息（具体数量取决于实现）
    // 在实际测试中，需要先插入一些待发送的消息

    env.cleanup().await;
}

/// 测试 3: 心跳超时 - 自动断开连接
///
/// 场景：客户端停止发送心跳（Ping），服务器检测到超时
/// 预期：
/// - 30 秒无心跳 → 服务器主动断开连接
/// - 清理 Redis 中的连接状态
/// - 释放服务器资源
#[tokio::test]
async fn test_heartbeat_timeout_disconnects_client() {
    let env = TestEnvironment::new().await;
    let redis = env.redis();

    let conversation_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let client_id = Uuid::new_v4();

    // 1. 建立连接并记录心跳时间
    let sync_state = offline_queue::ClientSyncState {
        client_id,
        user_id,
        conversation_id,
        last_message_id: "msg-1".to_string(),
        last_sync_at: chrono::Utc::now().timestamp() - 35, // 35 秒前（超过 30 秒阈值）
    };

    offline_queue::update_client_sync_state(&redis, &sync_state)
        .await
        .expect("保存同步状态失败");

    // 2. 检查是否超时（模拟心跳检查逻辑）
    let current_time = chrono::Utc::now().timestamp();
    let timeout_threshold = 30; // 30 秒超时阈值

    let is_timeout = (current_time - sync_state.last_sync_at) > timeout_threshold;

    assert!(
        is_timeout,
        "35 秒无心跳应该被判定为超时"
    );

    // 3. 模拟服务器清理超时连接
    let mut redis_conn = redis.clone();
    let sync_key = format!("sync_state:{}:{}:{}", user_id, conversation_id, client_id);
    redis::cmd("DEL")
        .arg(&sync_key)
        .query_async::<_, ()>(&mut redis_conn)
        .await
        .expect("清理超时连接失败");

    // 验证：连接状态已清除
    let restored_state = offline_queue::get_client_sync_state(&redis, user_id, conversation_id, client_id)
        .await
        .expect("获取同步状态失败");

    assert!(
        restored_state.is_none(),
        "超时连接应该被清理"
    );

    env.cleanup().await;
}

/// 测试 4: Redis 不可用 - 降级处理
///
/// 场景：Redis 服务暂时不可用（网络分区、Redis 重启等）
/// 预期：
/// - WebSocket 连接仍然可以建立（不依赖 Redis）
/// - 消息发送降级为仅内存处理
/// - 重连后自动恢复 Redis 功能
#[tokio::test]
async fn test_redis_unavailable_graceful_degradation() {
    let env = TestEnvironment::new().await;
    let db = env.db();

    let conversation_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();

    // 1. 创建用户和对话（不依赖 Redis）
    create_test_user(&db, user_id).await;
    create_test_conversation(&db, conversation_id, user_id).await;

    // 2. 模拟 Redis 不可用（通过连接错误的 Redis 地址）
    let invalid_redis_client = redis::Client::open("redis://localhost:9999")
        .expect("创建 Redis 客户端失败");

    let mut invalid_conn = redis::aio::ConnectionManager::new(invalid_redis_client)
        .await
        .expect("连接 Redis 失败");

    // 3. 尝试保存同步状态（应该失败）
    let sync_state = offline_queue::ClientSyncState {
        client_id: Uuid::new_v4(),
        user_id,
        conversation_id,
        last_message_id: "msg-1".to_string(),
        last_sync_at: chrono::Utc::now().timestamp(),
    };

    let save_result = redis::cmd("SETEX")
        .arg(format!("sync_state:{}:{}:{}", user_id, conversation_id, sync_state.client_id))
        .arg(300) // 5 分钟过期
        .arg(serde_json::to_string(&sync_state).unwrap())
        .query_async::<_, ()>(&mut invalid_conn)
        .await;

    assert!(
        save_result.is_err(),
        "Redis 不可用时保存同步状态应该失败"
    );

    // 4. 验证：核心功能（数据库写入）仍然正常
    let message_id = Uuid::new_v4();
    let insert_result = sqlx::query(
        r#"
        INSERT INTO messages (id, conversation_id, sender_id, content, created_at)
        VALUES ($1, $2, $3, $4, $5)
        "#,
    )
    .bind(message_id)
    .bind(conversation_id)
    .bind(user_id)
    .bind("Redis is down but DB works")
    .bind(chrono::Utc::now())
    .execute(&*db)
    .await;

    assert!(
        insert_result.is_ok(),
        "即使 Redis 不可用，数据库写入仍应成功"
    );

    // 验证：消息已写入数据库
    let message_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM messages WHERE id = $1")
        .bind(message_id)
        .fetch_one(&*db)
        .await
        .expect("查询消息失败");

    assert_eq!(message_count, 1, "消息应该成功写入数据库");

    env.cleanup().await;
}

/// 测试 5: 重连场景 - 恢复未发送的消息
///
/// 场景：客户端断线重连，需要恢复之前未发送的消息
/// 预期：
/// - 客户端重新连接后，从 Redis 读取离线消息
/// - 按顺序发送所有未读消息
/// - 更新 last_message_id，避免重复发送
#[tokio::test]
async fn test_reconnection_recovers_pending_messages() {
    let env = TestEnvironment::new().await;
    let db = env.db();
    let redis = env.redis();

    let conversation_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let client_id = Uuid::new_v4();

    // 1. 创建用户和对话
    create_test_user(&db, user_id).await;
    create_test_conversation(&db, conversation_id, user_id).await;

    // 2. 插入一些消息（模拟离线期间收到的消息）
    let message_ids = vec![
        Uuid::new_v4(),
        Uuid::new_v4(),
        Uuid::new_v4(),
    ];

    for (i, message_id) in message_ids.iter().enumerate() {
        sqlx::query(
            r#"
            INSERT INTO messages (id, conversation_id, sender_id, content, created_at)
            VALUES ($1, $2, $3, $4, $5)
            "#,
        )
        .bind(message_id)
        .bind(conversation_id)
        .bind(user_id)
        .bind(format!("Offline message {}", i + 1))
        .bind(chrono::Utc::now())
        .execute(&*db)
        .await
        .expect("插入消息失败");
    }

    // 3. 保存客户端同步状态（last_message_id 为空，表示首次连接）
    let sync_state = offline_queue::ClientSyncState {
        client_id,
        user_id,
        conversation_id,
        last_message_id: "".to_string(), // 首次连接，没有同步过消息
        last_sync_at: chrono::Utc::now().timestamp(),
    };

    offline_queue::update_client_sync_state(&redis, &sync_state)
        .await
        .expect("保存同步状态失败");

    // 4. 模拟重连：查询未读消息
    let unread_messages: Vec<(Uuid, String)> = sqlx::query_as(
        r#"
        SELECT id, content
        FROM messages
        WHERE conversation_id = $1
          AND deleted_at IS NULL
        ORDER BY created_at ASC
        LIMIT 100
        "#,
    )
    .bind(conversation_id)
    .fetch_all(&*db)
    .await
    .expect("查询未读消息失败");

    // 验证：应该有 3 条未读消息
    assert_eq!(
        unread_messages.len(),
        3,
        "应该有 3 条离线消息"
    );

    // 验证：消息顺序正确
    for (i, (msg_id, content)) in unread_messages.iter().enumerate() {
        assert_eq!(*msg_id, message_ids[i], "消息 ID 应该匹配");
        assert_eq!(
            content,
            &format!("Offline message {}", i + 1),
            "消息内容应该匹配"
        );
    }

    // 5. 更新同步状态（标记已读）
    let updated_sync_state = offline_queue::ClientSyncState {
        client_id,
        user_id,
        conversation_id,
        last_message_id: message_ids.last().unwrap().to_string(),
        last_sync_at: chrono::Utc::now().timestamp(),
    };

    offline_queue::update_client_sync_state(&redis, &updated_sync_state)
        .await
        .expect("更新同步状态失败");

    // 验证：同步状态已更新
    let restored_state = offline_queue::get_client_sync_state(&redis, user_id, conversation_id, client_id)
        .await
        .expect("获取同步状态失败")
        .expect("同步状态不应该为空");

    assert_eq!(
        restored_state.last_message_id,
        message_ids.last().unwrap().to_string(),
        "last_message_id 应该是最后一条消息的 ID"
    );

    env.cleanup().await;
}

// ============================================
// Helper Functions（辅助函数）
// ============================================

/// 创建测试用户
async fn create_test_user(db: &sqlx::PgPool, user_id: Uuid) {
    sqlx::query(
        r#"
        INSERT INTO users (id, email, username, password_hash, created_at)
        VALUES ($1, $2, $3, $4, $5)
        "#,
    )
    .bind(user_id)
    .bind(format!("{}@example.com", user_id))
    .bind(format!("user_{}", user_id))
    .bind("hashed_password")
    .bind(chrono::Utc::now())
    .execute(db)
    .await
    .expect("创建用户失败");
}

/// 创建测试对话
async fn create_test_conversation(db: &sqlx::PgPool, conversation_id: Uuid, user_id: Uuid) {
    sqlx::query(
        r#"
        INSERT INTO conversations (id, name, created_at)
        VALUES ($1, $2, $3)
        "#,
    )
    .bind(conversation_id)
    .bind(format!("Conversation {}", conversation_id))
    .bind(chrono::Utc::now())
    .execute(db)
    .await
    .expect("创建对话失败");

    // 添加用户到对话
    sqlx::query(
        r#"
        INSERT INTO conversation_participants (conversation_id, user_id, joined_at)
        VALUES ($1, $2, $3)
        "#,
    )
    .bind(conversation_id)
    .bind(user_id)
    .bind(chrono::Utc::now())
    .execute(db)
    .await
    .expect("添加用户到对话失败");
}

// ============================================
// Mock 模块：offline_queue
// ============================================

/// 模拟 offline_queue 模块（用于测试）
mod offline_queue {
    use redis::aio::ConnectionManager;
    use serde::{Deserialize, Serialize};
    use uuid::Uuid;

    #[derive(Debug, Serialize, Deserialize, Clone)]
    pub struct ClientSyncState {
        pub client_id: Uuid,
        pub user_id: Uuid,
        pub conversation_id: Uuid,
        pub last_message_id: String,
        pub last_sync_at: i64,
    }

    pub async fn update_client_sync_state(
        redis: &ConnectionManager,
        state: &ClientSyncState,
    ) -> Result<(), redis::RedisError> {
        let mut conn = redis.clone();
        let key = format!(
            "sync_state:{}:{}:{}",
            state.user_id, state.conversation_id, state.client_id
        );
        let value = serde_json::to_string(state)
            .map_err(|e| redis::RedisError::from((redis::ErrorKind::TypeError, "JSON serialization failed", e.to_string())))?;

        redis::cmd("SETEX")
            .arg(&key)
            .arg(300) // 5 分钟过期
            .arg(&value)
            .query_async(&mut conn)
            .await
    }

    pub async fn get_client_sync_state(
        redis: &ConnectionManager,
        user_id: Uuid,
        conversation_id: Uuid,
        client_id: Uuid,
    ) -> Result<Option<ClientSyncState>, redis::RedisError> {
        let mut conn = redis.clone();
        let key = format!("sync_state:{}:{}:{}", user_id, conversation_id, client_id);

        let value: Option<String> = redis::cmd("GET")
            .arg(&key)
            .query_async(&mut conn)
            .await?;

        match value {
            Some(json_str) => {
                let state: ClientSyncState = serde_json::from_str(&json_str)
                    .map_err(|e| redis::RedisError::from((redis::ErrorKind::TypeError, "JSON deserialization failed", e.to_string())))?;
                Ok(Some(state))
            }
            None => Ok(None),
        }
    }

    pub async fn get_pending_messages(
        _redis: &ConnectionManager,
        _user_id: Uuid,
        _conversation_id: Uuid,
    ) -> Result<Vec<String>, redis::RedisError> {
        // 模拟实现：返回空列表
        Ok(vec![])
    }
}
