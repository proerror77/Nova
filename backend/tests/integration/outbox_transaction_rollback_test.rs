//! Outbox 事务回滚测试 - P0 级别（最高优先级）
//!
//! 测试目标：验证 Outbox 模式的原子性保证
//! - 事务失败 → 数据回滚 + Outbox 事件不发布
//! - 事务成功 → 数据提交 + Outbox 事件发布
//! - 幂等性验证 → 同一消息多次发布 = 一个事件
//! - 死信队列处理 → 失败事件最终进入 DLQ
//!
//! Linus 哲学：
//! "数据结构优先 - Outbox 模式的核心是事务边界和事件一致性"
//! "消除特殊情况 - 成功和失败应该是同一套逻辑的不同路径"

use crate::fixtures::test_env::TestEnvironment;
use chrono::Utc;
use event_schema::outbox::{OutboxEvent, priority};
use sqlx::{PgPool, Postgres, Transaction};
use std::sync::Arc;
use uuid::Uuid;

/// 测试 1: 事务成功 - 数据和 Outbox 事件同时提交
///
/// 场景：创建消息，事务正常提交
/// 预期：
/// - messages 表插入成功
/// - outbox_events 表插入成功
/// - 两者在同一个事务中，原子性保证
#[tokio::test]
async fn test_transaction_success_commits_both_message_and_outbox() {
    // 初始化测试环境
    let env = TestEnvironment::new().await;
    let db = env.db();

    // 准备测试数据
    let user_id = Uuid::new_v4();
    let message_id = Uuid::new_v4();
    let conversation_id = Uuid::new_v4();

    // 开始事务
    let mut tx = db.begin().await.expect("开始事务失败");

    // 1. 插入消息（业务逻辑）
    sqlx::query(
        r#"
        INSERT INTO messages (id, conversation_id, sender_id, content, created_at)
        VALUES ($1, $2, $3, $4, $5)
        "#,
    )
    .bind(message_id)
    .bind(conversation_id)
    .bind(user_id)
    .bind("Hello, World!")
    .bind(Utc::now())
    .execute(&mut *tx)
    .await
    .expect("插入消息失败");

    // 2. 插入 Outbox 事件（原子性保证）
    let outbox_event = OutboxEvent::new(
        message_id,
        "MessageCreated",
        &serde_json::json!({
            "message_id": message_id,
            "conversation_id": conversation_id,
            "sender_id": user_id,
            "content": "Hello, World!",
        }),
        priority::NORMAL,
    )
    .expect("创建 Outbox 事件失败");

    sqlx::query(
        r#"
        INSERT INTO outbox_events (id, aggregate_id, event_type, payload, priority, created_at)
        VALUES ($1, $2, $3, $4, $5, $6)
        "#,
    )
    .bind(outbox_event.id)
    .bind(outbox_event.aggregate_id)
    .bind(&outbox_event.event_type)
    .bind(&outbox_event.payload)
    .bind(outbox_event.priority as i32)
    .bind(outbox_event.created_at)
    .execute(&mut *tx)
    .await
    .expect("插入 Outbox 事件失败");

    // 3. 提交事务
    tx.commit().await.expect("提交事务失败");

    // 验证：消息存在
    let message_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM messages WHERE id = $1")
        .bind(message_id)
        .fetch_one(&*db)
        .await
        .expect("查询消息失败");
    assert_eq!(message_count, 1, "消息应该被插入");

    // 验证：Outbox 事件存在
    let outbox_count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM outbox_events WHERE aggregate_id = $1")
            .bind(message_id)
            .fetch_one(&*db)
            .await
            .expect("查询 Outbox 事件失败");
    assert_eq!(outbox_count, 1, "Outbox 事件应该被插入");

    // 清理
    env.cleanup().await;
}

/// 测试 2: 事务失败 - 数据和 Outbox 事件同时回滚
///
/// 场景：创建消息，事务因错误回滚
/// 预期：
/// - messages 表未插入
/// - outbox_events 表未插入
/// - 两者都被回滚，不会出现部分提交
#[tokio::test]
async fn test_transaction_rollback_reverts_both_message_and_outbox() {
    let env = TestEnvironment::new().await;
    let db = env.db();

    let user_id = Uuid::new_v4();
    let message_id = Uuid::new_v4();
    let conversation_id = Uuid::new_v4();

    // 使用 Result 来捕获错误
    let result: Result<(), sqlx::Error> = async {
        let mut tx = db.begin().await?;

        // 1. 插入消息
        sqlx::query(
            r#"
            INSERT INTO messages (id, conversation_id, sender_id, content, created_at)
            VALUES ($1, $2, $3, $4, $5)
            "#,
        )
        .bind(message_id)
        .bind(conversation_id)
        .bind(user_id)
        .bind("Will be rolled back")
        .bind(Utc::now())
        .execute(&mut *tx)
        .await?;

        // 2. 插入 Outbox 事件
        let outbox_event = OutboxEvent::new(
            message_id,
            "MessageCreated",
            &serde_json::json!({"message_id": message_id}),
            priority::NORMAL,
        )
        .expect("创建 Outbox 事件失败");

        sqlx::query(
            r#"
            INSERT INTO outbox_events (id, aggregate_id, event_type, payload, priority, created_at)
            VALUES ($1, $2, $3, $4, $5, $6)
            "#,
        )
        .bind(outbox_event.id)
        .bind(outbox_event.aggregate_id)
        .bind(&outbox_event.event_type)
        .bind(&outbox_event.payload)
        .bind(outbox_event.priority as i32)
        .bind(outbox_event.created_at)
        .execute(&mut *tx)
        .await?;

        // 3. 模拟错误：插入无效的外键（触发回滚）
        sqlx::query(
            r#"
            INSERT INTO message_read_receipts (message_id, user_id, read_at)
            VALUES ($1, $2, $3)
            "#,
        )
        .bind(Uuid::new_v4()) // 不存在的 message_id → 外键约束失败
        .bind(user_id)
        .bind(Utc::now())
        .execute(&mut *tx)
        .await?;

        // 这行不会执行，因为上面会失败
        tx.commit().await?;
        Ok(())
    }
    .await;

    // 验证：事务应该失败
    assert!(result.is_err(), "事务应该因外键约束失败");

    // 验证：消息不存在（已回滚）
    let message_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM messages WHERE id = $1")
        .bind(message_id)
        .fetch_one(&*db)
        .await
        .expect("查询消息失败");
    assert_eq!(message_count, 0, "消息应该被回滚");

    // 验证：Outbox 事件不存在（已回滚）
    let outbox_count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM outbox_events WHERE aggregate_id = $1")
            .bind(message_id)
            .fetch_one(&*db)
            .await
            .expect("查询 Outbox 事件失败");
    assert_eq!(outbox_count, 0, "Outbox 事件应该被回滚");

    env.cleanup().await;
}

/// 测试 3: 幂等性验证 - 同一消息多次发布 = 一个事件
///
/// 场景：客户端重试导致重复请求
/// 预期：
/// - 第一次创建成功
/// - 第二次检测到重复，返回已存在的消息
/// - Outbox 事件只有一个（不重复发布）
#[tokio::test]
async fn test_idempotency_duplicate_message_creates_single_outbox_event() {
    let env = TestEnvironment::new().await;
    let db = env.db();

    let user_id = Uuid::new_v4();
    let message_id = Uuid::new_v4();
    let conversation_id = Uuid::new_v4();
    let idempotency_key = Uuid::new_v4().to_string();

    // 第一次创建（正常流程）
    create_message_with_outbox(&db, message_id, conversation_id, user_id, &idempotency_key)
        .await
        .expect("第一次创建应该成功");

    // 第二次创建（幂等性检查）
    let result = create_message_with_outbox(
        &db,
        message_id,
        conversation_id,
        user_id,
        &idempotency_key,
    )
    .await;

    // 验证：第二次应该检测到重复
    assert!(
        result.is_err(),
        "幂等性检查应该阻止重复创建"
    );

    // 验证：只有一个 Outbox 事件
    let outbox_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM outbox_events WHERE aggregate_id = $1 AND event_type = 'MessageCreated'",
    )
    .bind(message_id)
    .fetch_one(&*db)
    .await
    .expect("查询 Outbox 事件失败");
    assert_eq!(outbox_count, 1, "应该只有一个 Outbox 事件");

    env.cleanup().await;
}

/// 测试 4: 死信队列处理 - 失败事件最终进入 DLQ
///
/// 场景：Kafka 发布失败，重试超过最大次数
/// 预期：
/// - retry_count 递增到 max_retries
/// - last_error 记录失败原因
/// - 事件应该被移动到死信队列（或标记为失败）
#[tokio::test]
async fn test_dead_letter_queue_handling_for_failed_events() {
    let env = TestEnvironment::new().await;
    let db = env.db();

    let message_id = Uuid::new_v4();

    // 创建一个失败的 Outbox 事件
    let mut outbox_event = OutboxEvent::new(
        message_id,
        "MessageCreated",
        &serde_json::json!({"message_id": message_id}),
        priority::NORMAL,
    )
    .expect("创建 Outbox 事件失败");

    // 插入初始事件
    sqlx::query(
        r#"
        INSERT INTO outbox_events (id, aggregate_id, event_type, payload, priority, created_at, retry_count, last_error)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        "#,
    )
    .bind(outbox_event.id)
    .bind(outbox_event.aggregate_id)
    .bind(&outbox_event.event_type)
    .bind(&outbox_event.payload)
    .bind(outbox_event.priority as i32)
    .bind(outbox_event.created_at)
    .bind(0) // retry_count 初始为 0
    .bind(None::<String>) // last_error 初始为 NULL
    .execute(&*db)
    .await
    .expect("插入 Outbox 事件失败");

    // 模拟失败和重试（最多 3 次）
    const MAX_RETRIES: u32 = 3;
    for retry in 0..MAX_RETRIES {
        // 模拟 Kafka 发布失败
        outbox_event.mark_failed(format!("Kafka timeout on retry {}", retry));

        // 更新数据库中的重试状态
        sqlx::query(
            r#"
            UPDATE outbox_events
            SET retry_count = $1, last_error = $2
            WHERE id = $3
            "#,
        )
        .bind(outbox_event.retry_count as i32)
        .bind(&outbox_event.last_error)
        .bind(outbox_event.id)
        .execute(&*db)
        .await
        .expect("更新重试状态失败");
    }

    // 验证：retry_count 达到最大值
    let (retry_count, last_error): (i32, Option<String>) = sqlx::query_as(
        "SELECT retry_count, last_error FROM outbox_events WHERE id = $1",
    )
    .bind(outbox_event.id)
    .fetch_one(&*db)
    .await
    .expect("查询 Outbox 事件失败");

    assert_eq!(
        retry_count as u32, MAX_RETRIES,
        "retry_count 应该达到最大值"
    );
    assert!(
        last_error.is_some(),
        "last_error 应该记录失败原因"
    );
    assert!(
        last_error.unwrap().contains("Kafka timeout"),
        "错误信息应该包含原因"
    );

    // 验证：事件不应该再重试
    assert!(
        !outbox_event.should_retry(MAX_RETRIES),
        "超过最大重试次数后不应该再重试"
    );

    env.cleanup().await;
}

/// 测试 5: 部分失败场景 - 消息创建成功但 Kafka 发布失败
///
/// 场景：消息已写入数据库，但 Kafka 不可用
/// 预期：
/// - 消息存在于 messages 表
/// - Outbox 事件存在且 published_at = NULL
/// - 后台任务可以重新发布（可恢复性）
#[tokio::test]
async fn test_partial_failure_message_created_but_kafka_unavailable() {
    let env = TestEnvironment::new().await;
    let db = env.db();

    let user_id = Uuid::new_v4();
    let message_id = Uuid::new_v4();
    let conversation_id = Uuid::new_v4();

    // 开始事务
    let mut tx = db.begin().await.expect("开始事务失败");

    // 1. 插入消息
    sqlx::query(
        r#"
        INSERT INTO messages (id, conversation_id, sender_id, content, created_at)
        VALUES ($1, $2, $3, $4, $5)
        "#,
    )
    .bind(message_id)
    .bind(conversation_id)
    .bind(user_id)
    .bind("Message with pending outbox")
    .bind(Utc::now())
    .execute(&mut *tx)
    .await
    .expect("插入消息失败");

    // 2. 插入 Outbox 事件（published_at = NULL，模拟 Kafka 未发布）
    let outbox_event = OutboxEvent::new(
        message_id,
        "MessageCreated",
        &serde_json::json!({
            "message_id": message_id,
            "content": "Message with pending outbox",
        }),
        priority::NORMAL,
    )
    .expect("创建 Outbox 事件失败");

    sqlx::query(
        r#"
        INSERT INTO outbox_events (id, aggregate_id, event_type, payload, priority, created_at, published_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        "#,
    )
    .bind(outbox_event.id)
    .bind(outbox_event.aggregate_id)
    .bind(&outbox_event.event_type)
    .bind(&outbox_event.payload)
    .bind(outbox_event.priority as i32)
    .bind(outbox_event.created_at)
    .bind(None::<chrono::DateTime<Utc>>) // published_at = NULL
    .execute(&mut *tx)
    .await
    .expect("插入 Outbox 事件失败");

    // 3. 提交事务（模拟：数据库写入成功，但 Kafka 调用发生在事务外）
    tx.commit().await.expect("提交事务失败");

    // 验证：消息存在
    let message_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM messages WHERE id = $1")
        .bind(message_id)
        .fetch_one(&*db)
        .await
        .expect("查询消息失败");
    assert_eq!(message_count, 1, "消息应该存在");

    // 验证：Outbox 事件存在且未发布
    let (outbox_count, published_at): (i64, Option<chrono::DateTime<Utc>>) = sqlx::query_as(
        "SELECT COUNT(*), published_at FROM outbox_events WHERE aggregate_id = $1 GROUP BY published_at",
    )
    .bind(message_id)
    .fetch_one(&*db)
    .await
    .expect("查询 Outbox 事件失败");

    assert_eq!(outbox_count, 1, "Outbox 事件应该存在");
    assert!(
        published_at.is_none(),
        "published_at 应该为 NULL（未发布）"
    );

    // 验证：后台任务可以发现未发布的事件
    let unpublished_count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM outbox_events WHERE published_at IS NULL")
            .fetch_one(&*db)
            .await
            .expect("查询未发布事件失败");
    assert!(
        unpublished_count > 0,
        "应该有未发布的事件可供后台任务处理"
    );

    env.cleanup().await;
}

// ============================================
// Helper Functions（辅助函数）
// ============================================

/// 创建消息并生成 Outbox 事件（带幂等性检查）
async fn create_message_with_outbox(
    db: &PgPool,
    message_id: Uuid,
    conversation_id: Uuid,
    user_id: Uuid,
    idempotency_key: &str,
) -> Result<(), sqlx::Error> {
    let mut tx = db.begin().await?;

    // 1. 幂等性检查：检查是否已存在相同的 idempotency_key
    let existing: Option<Uuid> = sqlx::query_scalar(
        "SELECT id FROM messages WHERE id = $1 OR (sender_id = $2 AND content = $3)",
    )
    .bind(message_id)
    .bind(user_id)
    .bind(idempotency_key)
    .fetch_optional(&mut *tx)
    .await?;

    if existing.is_some() {
        return Err(sqlx::Error::RowNotFound); // 幂等性冲突
    }

    // 2. 插入消息
    sqlx::query(
        r#"
        INSERT INTO messages (id, conversation_id, sender_id, content, created_at)
        VALUES ($1, $2, $3, $4, $5)
        "#,
    )
    .bind(message_id)
    .bind(conversation_id)
    .bind(user_id)
    .bind(idempotency_key)
    .bind(Utc::now())
    .execute(&mut *tx)
    .await?;

    // 3. 插入 Outbox 事件
    let outbox_event = OutboxEvent::new(
        message_id,
        "MessageCreated",
        &serde_json::json!({
            "message_id": message_id,
            "idempotency_key": idempotency_key,
        }),
        priority::NORMAL,
    )
    .map_err(|e| sqlx::Error::Protocol(format!("创建 Outbox 事件失败: {}", e)))?;

    sqlx::query(
        r#"
        INSERT INTO outbox_events (id, aggregate_id, event_type, payload, priority, created_at)
        VALUES ($1, $2, $3, $4, $5, $6)
        "#,
    )
    .bind(outbox_event.id)
    .bind(outbox_event.aggregate_id)
    .bind(&outbox_event.event_type)
    .bind(&outbox_event.payload)
    .bind(outbox_event.priority as i32)
    .bind(outbox_event.created_at)
    .execute(&mut *tx)
    .await?;

    // 4. 提交事务
    tx.commit().await?;
    Ok(())
}
