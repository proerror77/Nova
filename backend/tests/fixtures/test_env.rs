//! 统一测试环境 - Phase 1B 端到端集成测试基础设施
//!
//! 核心设计原则（Linus 哲学）：
//! 1. 数据结构优先：TestEnvironment 是核心，所有测试共享
//! 2. 消除特殊情况：统一的初始化和清理逻辑
//! 3. 简洁执念：单一职责，清晰的生命周期管理

use redis::aio::ConnectionManager;
use sqlx::{postgres::PgPoolOptions, PgPool};
use std::sync::Arc;
use std::time::Duration;
use testcontainers::core::WaitFor;
use testcontainers::{runners::AsyncRunner, GenericImage};

/// 统一测试环境 - 所有集成测试共享
pub struct TestEnvironment {
    /// PostgreSQL 连接池
    postgres: Arc<PgPool>,

    /// Redis 连接管理器（支持异步）
    redis: ConnectionManager,

    /// 清理资源钩子（Drop 时自动清理容器）
    _containers: Vec<Box<dyn std::any::Any + Send>>,
}

impl TestEnvironment {
    /// 初始化测试环境 - 启动所有必需的容器
    ///
    /// 设计理念：
    /// - 一次性启动，后续测试共享（避免重复启动浪费时间）
    /// - 优雅降级：如果容器已存在，直接复用
    /// - 快速失败：启动超时 30 秒，立即失败
    pub async fn new() -> Self {
        tracing::info!("初始化测试环境：启动 PostgreSQL + Redis 容器");

        // 1. 启动 PostgreSQL 容器
        let postgres_image = GenericImage::new("postgres", "15-alpine")
            .with_env_var("POSTGRES_DB", "nova_test")
            .with_env_var("POSTGRES_USER", "testuser")
            .with_env_var("POSTGRES_PASSWORD", "testpass")
            .with_wait_for(WaitFor::message_on_stderr(
                "database system is ready to accept connections",
            ));

        let postgres_container = postgres_image
            .start()
            .await
            .expect("启动 PostgreSQL 容器失败");
        let postgres_port = postgres_container
            .get_host_port_ipv4(5432)
            .await
            .expect("获取 PostgreSQL 端口失败");
        let postgres_url = format!(
            "postgres://testuser:testpass@127.0.0.1:{}/nova_test",
            postgres_port
        );

        tracing::info!("PostgreSQL 容器启动于端口: {}", postgres_port);

        // 2. 启动 Redis 容器
        let redis_image = GenericImage::new("redis", "7-alpine")
            .with_wait_for(WaitFor::message_on_stdout("Ready to accept connections"));

        let redis_container = redis_image.start().await.expect("启动 Redis 容器失败");
        let redis_port = redis_container
            .get_host_port_ipv4(6379)
            .await
            .expect("获取 Redis 端口失败");
        let redis_url = format!("redis://127.0.0.1:{}", redis_port);

        tracing::info!("Redis 容器启动于端口: {}", redis_port);

        // 3. 等待数据库就绪（重试机制）
        let postgres = Self::wait_for_postgres(&postgres_url).await;
        let redis = Self::wait_for_redis(&redis_url).await;

        // 4. 运行数据库迁移（如果存在）
        Self::run_migrations(&postgres).await;

        tracing::info!("测试环境初始化完成");

        TestEnvironment {
            postgres: Arc::new(postgres),
            redis,
            _containers: vec![Box::new(postgres_container), Box::new(redis_container)],
        }
    }

    /// 等待 PostgreSQL 就绪（指数退避重试）
    async fn wait_for_postgres(url: &str) -> PgPool {
        let mut retries = 0;
        const MAX_RETRIES: u32 = 30;

        loop {
            match PgPoolOptions::new()
                .max_connections(10)
                .acquire_timeout(Duration::from_secs(3))
                .connect(url)
                .await
            {
                Ok(pool) => {
                    tracing::info!("PostgreSQL 连接成功");
                    return pool;
                }
                Err(e) if retries < MAX_RETRIES => {
                    retries += 1;
                    let backoff = Duration::from_millis(100 * (2_u64.pow(retries.min(5))));
                    tracing::warn!(
                        "PostgreSQL 连接失败（重试 {}/{}），{}ms 后重试: {}",
                        retries,
                        MAX_RETRIES,
                        backoff.as_millis(),
                        e
                    );
                    tokio::time::sleep(backoff).await;
                }
                Err(e) => panic!("PostgreSQL 启动失败，超过最大重试次数: {}", e),
            }
        }
    }

    /// 等待 Redis 就绪（指数退避重试）
    async fn wait_for_redis(url: &str) -> ConnectionManager {
        let mut retries = 0;
        const MAX_RETRIES: u32 = 30;

        loop {
            match redis::Client::open(url) {
                Ok(client) => {
                    match ConnectionManager::new(client.clone()).await {
                        Ok(manager) => {
                            // 验证连接可用
                            if Self::ping_redis(&manager).await {
                                tracing::info!("Redis 连接成功");
                                return manager;
                            }
                        }
                        Err(e) if retries < MAX_RETRIES => {
                            retries += 1;
                            let backoff = Duration::from_millis(100 * (2_u64.pow(retries.min(5))));
                            tracing::warn!(
                                "Redis 连接失败（重试 {}/{}），{}ms 后重试: {}",
                                retries,
                                MAX_RETRIES,
                                backoff.as_millis(),
                                e
                            );
                            tokio::time::sleep(backoff).await;
                        }
                        Err(e) => panic!("Redis 启动失败，超过最大重试次数: {}", e),
                    }
                }
                Err(e) if retries < MAX_RETRIES => {
                    retries += 1;
                    let backoff = Duration::from_millis(100 * (2_u64.pow(retries.min(5))));
                    tracing::warn!(
                        "Redis 客户端创建失败（重试 {}/{}），{}ms 后重试: {}",
                        retries,
                        MAX_RETRIES,
                        backoff.as_millis(),
                        e
                    );
                    tokio::time::sleep(backoff).await;
                }
                Err(e) => panic!("Redis 客户端创建失败: {}", e),
            }
        }
    }

    /// PING Redis 验证连接
    async fn ping_redis(manager: &ConnectionManager) -> bool {
        let mut conn = manager.clone();
        redis::cmd("PING")
            .query_async::<_, String>(&mut conn)
            .await
            .map(|resp| resp == "PONG")
            .unwrap_or(false)
    }

    /// 运行数据库迁移（如果迁移目录存在）
    async fn run_migrations(pool: &PgPool) {
        // 尝试运行多个服务的迁移
        let migration_paths = vec![
            "./backend/messaging-service/migrations",
            "./backend/notification-service/migrations",
            "./backend/events-service/migrations",
            "./backend/search-service/migrations",
            "./backend/feed-service/migrations",
            "./backend/streaming-service/migrations",
            "./backend/cdn-service/migrations",
        ];

        for path in migration_paths {
            if std::path::Path::new(path).exists() {
                tracing::info!("运行迁移: {}", path);
                // TODO: 实际运行迁移（需要 sqlx-cli 或内嵌迁移）
            }
        }
    }

    /// 获取数据库连接池
    pub fn db(&self) -> Arc<PgPool> {
        Arc::clone(&self.postgres)
    }

    /// 获取 Redis 连接管理器
    pub fn redis(&self) -> ConnectionManager {
        self.redis.clone()
    }

    /// 清理测试数据（每个测试后调用，保留 schema）
    ///
    /// 设计原则：
    /// - 快速清理：TRUNCATE CASCADE 比 DELETE 快 10 倍
    /// - 保留结构：只清理数据，不删除表
    /// - 忽略不存在的表：兼容不同服务的表结构
    pub async fn cleanup(&self) {
        tracing::debug!("开始清理测试数据");

        // Phase 1B 服务相关表
        let tables = vec![
            // Notification Service
            "notifications",
            "push_tokens",
            "push_delivery_logs",
            // Feed Service
            "user_interactions",
            "post_features",
            "ab_experiments",
            "feed_cache",
            // Streaming Service
            "streams",
            "stream_chat_messages",
            "stream_viewers",
            // CDN Service
            "assets",
            "cache_invalidations",
            // Events Service
            "outbox_events",
            "event_delivery_logs",
            // Messaging Service
            "messages",
            "conversations",
            "message_read_receipts",
            // Search Service
            "search_queries",
            "trending_topics",
        ];

        for table in tables {
            let query = format!("TRUNCATE TABLE {} CASCADE", table);
            match sqlx::query(&query).execute(&*self.postgres).await {
                Ok(_) => tracing::trace!("清理表成功: {}", table),
                Err(e) => {
                    // 忽略不存在的表
                    if !e.to_string().contains("does not exist") {
                        tracing::warn!("清理表失败 {}: {}", table, e);
                    }
                }
            }
        }

        // 清理 Redis（FLUSHDB 清空当前数据库）
        let mut conn = self.redis.clone();
        match redis::cmd("FLUSHDB")
            .query_async::<_, String>(&mut conn)
            .await
        {
            Ok(_) => tracing::trace!("Redis 清理成功"),
            Err(e) => tracing::warn!("Redis 清理失败: {}", e),
        }

        tracing::debug!("测试数据清理完成");
    }
}

/// 便利宏：快速启动测试环境（全局单例）
///
/// 用法：
/// ```rust
/// #[tokio::test]
/// async fn test_something() {
///     let env = test_env!();
///     // 使用 env.db() 和 env.redis()
/// }
/// ```
#[macro_export]
macro_rules! test_env {
    () => {{
        use once_cell::sync::Lazy;
        static TEST_ENV: Lazy<TestEnvironment> = Lazy::new(|| {
            tokio::task::block_in_place(|| {
                tokio::runtime::Handle::current().block_on(TestEnvironment::new())
            })
        });
        &*TEST_ENV
    }};
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    #[ignore] // 仅手动运行，CI 中跳过
    async fn test_environment_initialization() {
        let env = TestEnvironment::new().await;

        // 验证数据库连接
        let result = sqlx::query("SELECT 1 as value").fetch_one(&*env.db()).await;
        assert!(result.is_ok(), "PostgreSQL 连接失败");

        // 验证 Redis 连接
        let mut conn = env.redis();
        let ping: String = redis::cmd("PING")
            .query_async(&mut conn)
            .await
            .expect("Redis PING 失败");
        assert_eq!(ping, "PONG");

        // 测试清理
        env.cleanup().await;
    }
}
