//! 测试断言工具 - 等待、性能和数据一致性验证
//!
//! Linus 哲学：
//! - 消除重复：统一的等待和断言逻辑
//! - 好品味：清晰的错误信息，而不是神秘的断言失败

use sqlx::PgPool;
use std::future::Future;
use std::time::{Duration, Instant};
use uuid::Uuid;

// ============================================
// 异步等待工具
// ============================================

/// 异步等待条件满足（带超时保护）
///
/// # 参数
/// - `f`: 返回 `bool` 的异步闭包
/// - `timeout`: 最大等待时间
/// - `poll_interval`: 轮询间隔
///
/// # 示例
/// ```rust
/// wait_for(
///     || async { check_notification_created(db, user_id).await },
///     Duration::from_secs(10),
///     Duration::from_millis(100),
/// ).await.expect("通知未创建");
/// ```
pub async fn wait_for<F, Fut>(
    mut f: F,
    timeout: Duration,
    poll_interval: Duration,
) -> Result<(), String>
where
    F: FnMut() -> Fut,
    Fut: Future<Output = bool>,
{
    let start = Instant::now();
    let mut attempts = 0;

    loop {
        attempts += 1;

        if f().await {
            tracing::debug!(
                "条件满足（{}次尝试，耗时 {}ms）",
                attempts,
                start.elapsed().as_millis()
            );
            return Ok(());
        }

        if start.elapsed() > timeout {
            return Err(format!(
                "等待超时（{}ms），尝试 {} 次后条件仍未满足",
                timeout.as_millis(),
                attempts
            ));
        }

        tokio::time::sleep(poll_interval).await;
    }
}

/// 等待条件满足（默认超时 10 秒，轮询 100ms）
#[allow(dead_code)]
pub async fn wait_for_default<F, Fut>(f: F) -> Result<(), String>
where
    F: FnMut() -> Fut,
    Fut: Future<Output = bool>,
{
    wait_for(f, Duration::from_secs(10), Duration::from_millis(100)).await
}

// ============================================
// 性能断言
// ============================================

/// 断言操作延迟在可接受范围内
///
/// # 示例
/// ```rust
/// let start = Instant::now();
/// send_message(&db, sender_id, receiver_id).await;
/// assert_latency(start.elapsed(), 500, "send_message");
/// ```
pub fn assert_latency(duration: Duration, max_ms: u64, context: &str) {
    let latency_ms = duration.as_millis() as u64;
    assert!(
        latency_ms <= max_ms,
        "❌ 性能不达标: {} 延迟 {}ms > 阈值 {}ms",
        context,
        latency_ms,
        max_ms
    );
    tracing::info!(
        "✅ 性能达标: {} 延迟 {}ms ≤ {}ms",
        context,
        latency_ms,
        max_ms
    );
}

/// 断言 P95 延迟（对批量操作）
#[allow(dead_code)]
pub fn assert_p95_latency(durations: &[Duration], max_ms: u64, context: &str) {
    let mut sorted: Vec<_> = durations.iter().map(|d| d.as_millis() as u64).collect();
    sorted.sort_unstable();

    let p95_index = (sorted.len() as f64 * 0.95) as usize;
    let p95 = sorted.get(p95_index).copied().unwrap_or(0);

    assert!(
        p95 <= max_ms,
        "❌ P95 性能不达标: {} P95={}ms > 阈值 {}ms",
        context,
        p95,
        max_ms
    );
    tracing::info!("✅ P95 性能达标: {} P95={}ms ≤ {}ms", context, p95, max_ms);
}

/// 断言吞吐量（每秒操作数）
pub fn assert_throughput(
    operations: usize,
    duration: Duration,
    min_ops_per_sec: f64,
    context: &str,
) {
    let ops_per_sec = operations as f64 / duration.as_secs_f64();
    assert!(
        ops_per_sec >= min_ops_per_sec,
        "❌ 吞吐量不达标: {} {:.2} ops/sec < 阈值 {:.2} ops/sec",
        context,
        ops_per_sec,
        min_ops_per_sec
    );
    tracing::info!(
        "✅ 吞吐量达标: {} {:.2} ops/sec ≥ {:.2} ops/sec",
        context,
        ops_per_sec,
        min_ops_per_sec
    );
}

// ============================================
// 数据一致性断言
// ============================================

/// 断言 Outbox 事件已创建（事件溯源核心）
///
/// 验证：写入数据库的操作都生成了对应的事件
#[allow(dead_code)]
pub async fn assert_outbox_event_exists(
    db: &PgPool,
    aggregate_id: Uuid,
    event_type: &str,
) -> Result<(), String> {
    let exists = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(
            SELECT 1 FROM outbox_events
            WHERE aggregate_id = $1 AND event_type = $2
        )",
    )
    .bind(aggregate_id)
    .bind(event_type)
    .fetch_one(db)
    .await
    .map_err(|e| format!("数据库查询失败: {}", e))?;

    if exists {
        tracing::debug!("✅ Outbox 事件存在: {} {}", event_type, aggregate_id);
        Ok(())
    } else {
        Err(format!(
            "❌ Outbox 事件不存在: {} {}",
            event_type, aggregate_id
        ))
    }
}

/// 断言记录存在
pub async fn assert_record_exists(
    db: &PgPool,
    table: &str,
    id_column: &str,
    id: Uuid,
) -> Result<(), String> {
    let query = format!(
        "SELECT EXISTS(SELECT 1 FROM {} WHERE {} = $1)",
        table, id_column
    );

    let exists = sqlx::query_scalar::<_, bool>(&query)
        .bind(id)
        .fetch_one(db)
        .await
        .map_err(|e| format!("数据库查询失败: {}", e))?;

    if exists {
        tracing::debug!("✅ 记录存在: {}.{} = {}", table, id_column, id);
        Ok(())
    } else {
        Err(format!("❌ 记录不存在: {}.{} = {}", table, id_column, id))
    }
}

/// 断言记录不存在（验证删除操作）
#[allow(dead_code)]
pub async fn assert_record_not_exists(
    db: &PgPool,
    table: &str,
    id_column: &str,
    id: Uuid,
) -> Result<(), String> {
    let query = format!(
        "SELECT EXISTS(SELECT 1 FROM {} WHERE {} = $1)",
        table, id_column
    );

    let exists = sqlx::query_scalar::<_, bool>(&query)
        .bind(id)
        .fetch_one(db)
        .await
        .map_err(|e| format!("数据库查询失败: {}", e))?;

    if !exists {
        tracing::debug!("✅ 记录已删除: {}.{} = {}", table, id_column, id);
        Ok(())
    } else {
        Err(format!("❌ 记录仍存在: {}.{} = {}", table, id_column, id))
    }
}

/// 断言记录数量
#[allow(dead_code)]
pub async fn assert_record_count(
    db: &PgPool,
    table: &str,
    expected_count: i64,
) -> Result<(), String> {
    let query = format!("SELECT COUNT(*) FROM {}", table);

    let count = sqlx::query_scalar::<_, i64>(&query)
        .fetch_one(db)
        .await
        .map_err(|e| format!("数据库查询失败: {}", e))?;

    if count == expected_count {
        tracing::debug!("✅ 记录数量正确: {} count = {}", table, count);
        Ok(())
    } else {
        Err(format!(
            "❌ 记录数量不匹配: {} count = {} (期望 {})",
            table, count, expected_count
        ))
    }
}

/// 断言 Redis 键存在
#[allow(dead_code)]
pub async fn assert_redis_key_exists(
    redis: &mut redis::aio::ConnectionManager,
    key: &str,
) -> Result<(), String> {
    let exists: bool = redis::cmd("EXISTS")
        .arg(key)
        .query_async(redis)
        .await
        .map_err(|e| format!("Redis 查询失败: {}", e))?;

    if exists {
        tracing::debug!("✅ Redis 键存在: {}", key);
        Ok(())
    } else {
        Err(format!("❌ Redis 键不存在: {}", key))
    }
}

/// 断言 Redis 键不存在
#[allow(dead_code)]
pub async fn assert_redis_key_not_exists(
    redis: &mut redis::aio::ConnectionManager,
    key: &str,
) -> Result<(), String> {
    let exists: bool = redis::cmd("EXISTS")
        .arg(key)
        .query_async(redis)
        .await
        .map_err(|e| format!("Redis 查询失败: {}", e))?;

    if !exists {
        tracing::debug!("✅ Redis 键已过期: {}", key);
        Ok(())
    } else {
        Err(format!("❌ Redis 键仍存在: {}", key))
    }
}

// ============================================
// 事件一致性断言
// ============================================

/// 断言事件已发布到 Kafka（通过 outbox 状态）
#[allow(dead_code)]
pub async fn assert_event_published(db: &PgPool, event_id: Uuid) -> Result<(), String> {
    let status: String = sqlx::query_scalar("SELECT status FROM outbox_events WHERE id = $1")
        .bind(event_id)
        .fetch_one(db)
        .await
        .map_err(|e| format!("查询事件状态失败: {}", e))?;

    if status == "published" {
        tracing::debug!("✅ 事件已发布: {}", event_id);
        Ok(())
    } else {
        Err(format!("❌ 事件未发布: {} (状态: {})", event_id, status))
    }
}

/// 断言事件顺序正确（同一聚合根）
#[allow(dead_code)]
pub async fn assert_event_ordering(db: &PgPool, aggregate_id: Uuid) -> Result<(), String> {
    let events: Vec<(Uuid, i64)> = sqlx::query_as(
        "SELECT id, sequence_number FROM outbox_events
         WHERE aggregate_id = $1
         ORDER BY sequence_number",
    )
    .bind(aggregate_id)
    .fetch_all(db)
    .await
    .map_err(|e| format!("查询事件失败: {}", e))?;

    // 验证序列号连续
    for (i, (id, seq)) in events.iter().enumerate() {
        let expected_seq = i as i64 + 1;
        if *seq != expected_seq {
            return Err(format!(
                "❌ 事件序列号不连续: event {} seq={} (期望 {})",
                id, seq, expected_seq
            ));
        }
    }

    tracing::debug!(
        "✅ 事件顺序正确: aggregate {} 有 {} 个事件",
        aggregate_id,
        events.len()
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_wait_for_success() {
        let mut counter = 0;

        let result = wait_for(
            || {
                counter += 1;
                async move { counter >= 3 }
            },
            Duration::from_secs(5),
            Duration::from_millis(10),
        )
        .await;

        assert!(result.is_ok());
        assert_eq!(counter, 3);
    }

    #[tokio::test]
    async fn test_wait_for_timeout() {
        let result = wait_for(
            || async { false },
            Duration::from_millis(100),
            Duration::from_millis(10),
        )
        .await;

        assert!(result.is_err());
        assert!(result.unwrap_err().contains("超时"));
    }

    #[test]
    fn test_assert_latency_pass() {
        let duration = Duration::from_millis(300);
        assert_latency(duration, 500, "test_operation");
    }

    #[test]
    #[should_panic(expected = "性能不达标")]
    fn test_assert_latency_fail() {
        let duration = Duration::from_millis(600);
        assert_latency(duration, 500, "test_operation");
    }

    #[test]
    fn test_assert_throughput_pass() {
        let duration = Duration::from_secs(1);
        assert_throughput(1500, duration, 1000.0, "test_operation");
    }

    #[test]
    #[should_panic(expected = "吞吐量不达标")]
    fn test_assert_throughput_fail() {
        let duration = Duration::from_secs(1);
        assert_throughput(500, duration, 1000.0, "test_operation");
    }
}
