/// Test fixtures and utilities for integration tests
/// Provides database setup, test data creation, and cleanup
use chrono::Utc;
use sqlx::postgres::PgPoolOptions;
use sqlx::PgPool;
use std::time::Duration;
use user_service::models::{OAuthConnection, Post, PostImage, User};
use uuid::Uuid;

// ============================================
// Database Setup
// ============================================

/// Create a test database pool with migrations
pub async fn create_test_pool() -> PgPool {
    // 默认指向 docker-compose 暴露的 Postgres 端口与默认数据库
    // 可通过环境变量 DATABASE_URL 覆盖
    let database_url = std::env::var("DATABASE_URL").unwrap_or_else(|_| {
        // postgres://user:pass@host:port/db
        "postgres://postgres:postgres@localhost:55432/nova_auth".to_string()
    });

    eprintln!("[tests] Connecting to PostgreSQL at {}", database_url);

    // 尝试重试连接，适配 CI/本地环境中容器启动的延迟
    let mut last_err: Option<anyhow::Error> = None;
    for attempt in 1..=30u32 {
        // 固定 1 秒间隔，最多 30 秒
        let backoff = Duration::from_secs(1);

        match PgPoolOptions::new()
            .max_connections(5)
            .acquire_timeout(Duration::from_secs(3)) // 增加超时到 3 秒
            .connect(&database_url)
            .await
        {
            Ok(pool) => {
                // 健康检查：确保数据库真正就绪（能执行查询）
                match sqlx::query("SELECT 1").fetch_one(&pool).await {
                    Ok(_) => {
                        eprintln!("[tests] PostgreSQL ready after {} attempts", attempt);
                        // 迁移：忽略历史环境中缺失的版本，避免阻塞本地/CI
                        let mut migrator = sqlx::migrate!("../migrations");
                        migrator.set_ignore_missing(true);
                        if let Err(e) = migrator.run(&pool).await {
                            panic!("Failed to run migrations: {}", e);
                        }
                        return pool;
                    }
                    Err(e) => {
                        eprintln!(
                            "[tests] PostgreSQL connected but not ready (attempt {}): {}",
                            attempt, e
                        );
                        last_err = Some(anyhow::anyhow!(e));
                        tokio::time::sleep(backoff).await;
                        continue;
                    }
                }
            }
            Err(e) => {
                last_err = Some(anyhow::anyhow!(e));
                eprintln!(
                    "[tests] waiting for Postgres (attempt {}/30): {:?}",
                    attempt, backoff
                );
                tokio::time::sleep(backoff).await;
            }
        }
    }

    panic!(
        "Failed to connect to test database after 30 retries (30 seconds): {}",
        last_err.unwrap()
    );
}

/// Clean up test data after tests
pub async fn cleanup_test_data(pool: &PgPool) {
    // Delete in order to respect foreign key constraints
    sqlx::query("DELETE FROM upload_sessions")
        .execute(pool)
        .await
        .ok();

    sqlx::query("DELETE FROM post_images")
        .execute(pool)
        .await
        .ok();

    sqlx::query("DELETE FROM post_metadata")
        .execute(pool)
        .await
        .ok();

    sqlx::query("DELETE FROM posts").execute(pool).await.ok();

    sqlx::query("DELETE FROM oauth_connections")
        .execute(pool)
        .await
        .ok();

    sqlx::query("DELETE FROM sessions").execute(pool).await.ok();

    sqlx::query("DELETE FROM refresh_tokens")
        .execute(pool)
        .await
        .ok();

    sqlx::query("DELETE FROM email_verifications")
        .execute(pool)
        .await
        .ok();

    sqlx::query("DELETE FROM users").execute(pool).await.ok();
}

// ============================================
// Test User Creation
// ============================================

/// Create a test user with default values
pub async fn create_test_user(pool: &PgPool) -> User {
    create_test_user_with_email(pool, &format!("test-{}@example.com", Uuid::new_v4())).await
}

/// Create a test user with specific email
pub async fn create_test_user_with_email(pool: &PgPool, email: &str) -> User {
    let username = format!(
        "user_{}",
        Uuid::new_v4()
            .to_string()
            .chars()
            .take(8)
            .collect::<String>()
    );
    let password_hash = "$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5oe2QRfhJK2Gu"; // "password"

    sqlx::query_as::<_, User>(
        r#"
        INSERT INTO users (email, username, password_hash, email_verified, is_active)
        VALUES ($1, $2, $3, true, true)
        RETURNING id, email, username, password_hash, email_verified, is_active,
                  failed_login_attempts, locked_until, created_at, updated_at, last_login_at
        "#,
    )
    .bind(email)
    .bind(&username)
    .bind(password_hash)
    .fetch_one(pool)
    .await
    .expect("Failed to create test user")
}

// ============================================
// Test Post Creation
// ============================================

/// Create a test post with default values
pub async fn create_test_post(pool: &PgPool, user_id: Uuid) -> Post {
    create_test_post_with_caption(pool, user_id, Some("Test post"), "pending").await
}

/// Create a test post with specific caption and status
pub async fn create_test_post_with_caption(
    pool: &PgPool,
    user_id: Uuid,
    caption: Option<&str>,
    status: &str,
) -> Post {
    let post = sqlx::query_as::<_, Post>(
        r#"
        INSERT INTO posts (user_id, caption, image_key, status)
        VALUES ($1, $2, $3, $4)
        RETURNING id, user_id, caption, image_key, image_sizes, status, created_at, updated_at, soft_delete
        "#,
    )
    .bind(user_id)
    .bind(caption)
    .bind(format!("posts/{}/original", Uuid::new_v4()))
    .bind(status)
    .fetch_one(pool)
    .await
    .expect("Failed to create test post");

    post
}

/// Create a test post with images in specific status
pub async fn create_test_post_with_images(
    pool: &PgPool,
    user_id: Uuid,
    caption: Option<&str>,
    post_status: &str,
    image_status: &str,
) -> (Post, Vec<PostImage>) {
    let post = create_test_post_with_caption(pool, user_id, caption, post_status).await;

    // Create image variants
    let mut images = Vec::new();
    for variant in &["thumbnail", "medium", "original"] {
        let s3_key = format!("posts/{}/{}", post.id, variant);
        let url = if image_status == "completed" {
            Some(format!("https://d123456.cloudfront.net/{}", s3_key))
        } else {
            None
        };

        let image = sqlx::query_as::<_, PostImage>(
            r#"
            INSERT INTO post_images (post_id, s3_key, size_variant, status, url)
            VALUES ($1, $2, $3, $4, $5)
            RETURNING id, post_id, s3_key, status, size_variant, file_size, width, height, url, error_message, created_at, updated_at
            "#,
        )
        .bind(post.id)
        .bind(&s3_key)
        .bind(variant)
        .bind(image_status)
        .bind(url)
        .fetch_one(pool)
        .await
        .expect("Failed to create test post_image");

        images.push(image);
    }

    (post, images)
}

/// Soft delete a post
pub async fn soft_delete_post(pool: &PgPool, post_id: Uuid) {
    sqlx::query(
        r#"
        UPDATE posts
        SET soft_delete = NOW()
        WHERE id = $1
        "#,
    )
    .bind(post_id)
    .execute(pool)
    .await
    .expect("Failed to soft delete post");
}

// ============================================
// Test Post Metadata
// ============================================

/// Update post metadata with specific engagement counts
pub async fn update_post_metadata(
    pool: &PgPool,
    post_id: Uuid,
    like_count: i32,
    comment_count: i32,
    view_count: i32,
) {
    sqlx::query(
        r#"
        UPDATE post_metadata
        SET like_count = $1, comment_count = $2, view_count = $3
        WHERE post_id = $4
        "#,
    )
    .bind(like_count)
    .bind(comment_count)
    .bind(view_count)
    .bind(post_id)
    .execute(pool)
    .await
    .expect("Failed to update post metadata");
}

// ============================================
// Test Upload Session
// ============================================

/// Create a test upload session
pub async fn create_test_upload_session(pool: &PgPool, post_id: Uuid) -> String {
    use rand::Rng;
    let mut rng = rand::thread_rng();
    let token_bytes: [u8; 32] = rng.gen();
    let upload_token = hex::encode(token_bytes);

    let expires_at = Utc::now() + chrono::Duration::hours(1);

    sqlx::query(
        r#"
        INSERT INTO upload_sessions (post_id, upload_token, expires_at)
        VALUES ($1, $2, $3)
        "#,
    )
    .bind(post_id)
    .bind(&upload_token)
    .bind(expires_at)
    .execute(pool)
    .await
    .expect("Failed to create upload session");

    upload_token
}

// ============================================
// Batch Operations
// ============================================

/// Create multiple test posts for pagination testing
pub async fn create_test_posts_batch(pool: &PgPool, user_id: Uuid, count: usize) -> Vec<Post> {
    let mut posts = Vec::new();

    for i in 0..count {
        let caption_str = format!("Test post {}", i + 1);
        let post =
            create_test_post_with_caption(pool, user_id, Some(&caption_str), "published").await;
        posts.push(post);

        // Small delay to ensure different timestamps
        tokio::time::sleep(tokio::time::Duration::from_millis(10)).await;
    }

    posts
}

// ============================================
// OAuth Test Helpers
// ============================================

/// Create a test OAuth connection for a user
pub async fn create_test_oauth_connection(
    pool: &PgPool,
    user_id: Uuid,
    provider: &str,
    provider_user_id: &str,
) -> OAuthConnection {
    use sha2::{Digest, Sha256};

    let id = Uuid::new_v4();
    let now = Utc::now();

    // Hash tokens for storage
    let mut hasher = Sha256::new();
    hasher.update(b"test_access_token");
    let access_token_hash = hex::encode(hasher.finalize());

    let mut hasher = Sha256::new();
    hasher.update(b"test_refresh_token");
    let refresh_token_hash = hex::encode(hasher.finalize());

    let expires_at = now + chrono::Duration::hours(1);

    sqlx::query_as::<_, OAuthConnection>(
        r#"
        INSERT INTO oauth_connections
        (id, user_id, provider, provider_user_id, provider_email, display_name,
         access_token_hash, refresh_token_hash, token_expires_at, created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
        RETURNING id, user_id, provider, provider_user_id, provider_email, display_name,
                  access_token_hash, refresh_token_hash, token_expires_at, created_at, updated_at
        "#,
    )
    .bind(id)
    .bind(user_id)
    .bind(provider)
    .bind(provider_user_id)
    .bind(format!("{}@{}.com", provider_user_id, provider))
    .bind(Some(format!("Test {} User", provider)))
    .bind(access_token_hash)
    .bind(Some(refresh_token_hash))
    .bind(Some(expires_at))
    .bind(now)
    .bind(now)
    .fetch_one(pool)
    .await
    .expect("Failed to create test OAuth connection")
}

/// Find OAuth connection by provider and provider user ID
pub async fn find_oauth_connection(
    pool: &PgPool,
    provider: &str,
    provider_user_id: &str,
) -> Option<OAuthConnection> {
    sqlx::query_as::<_, OAuthConnection>(
        r#"
        SELECT id, user_id, provider, provider_user_id, provider_email, display_name,
               access_token_hash, refresh_token_hash, token_expires_at, created_at, updated_at
        FROM oauth_connections
        WHERE provider = $1 AND provider_user_id = $2
        "#,
    )
    .bind(provider)
    .bind(provider_user_id)
    .fetch_optional(pool)
    .await
    .ok()
    .flatten()
}

/// Count OAuth connections for a user
pub async fn count_user_oauth_connections(pool: &PgPool, user_id: Uuid) -> i64 {
    sqlx::query_scalar::<_, i64>(
        r#"
        SELECT COUNT(*) FROM oauth_connections WHERE user_id = $1
        "#,
    )
    .bind(user_id)
    .fetch_one(pool)
    .await
    .unwrap_or(0)
}

// ============================================
// Security Testing Helpers
// ============================================

/// Create a test user with unverified email
pub async fn create_unverified_user(pool: &PgPool, email: &str, password_hash: &str) -> User {
    let username = format!(
        "user_{}",
        Uuid::new_v4()
            .to_string()
            .chars()
            .take(8)
            .collect::<String>()
    );

    sqlx::query_as::<_, User>(
        r#"
        INSERT INTO users (email, username, password_hash, email_verified, is_active)
        VALUES ($1, $2, $3, false, true)
        RETURNING id, email, username, password_hash, email_verified, is_active,
                  failed_login_attempts, locked_until, created_at, updated_at, last_login_at
        "#,
    )
    .bind(email)
    .bind(&username)
    .bind(password_hash)
    .fetch_one(pool)
    .await
    .expect("Failed to create unverified user")
}

/// Lock a user account until specified time
pub async fn lock_user_account(pool: &PgPool, user_id: Uuid, locked_until: chrono::DateTime<Utc>) {
    sqlx::query(
        r#"
        UPDATE users
        SET failed_login_attempts = 5, locked_until = $1
        WHERE id = $2
        "#,
    )
    .bind(locked_until)
    .bind(user_id)
    .execute(pool)
    .await
    .expect("Failed to lock user account");
}

/// Get user's failed login attempts count
pub async fn get_failed_login_attempts(pool: &PgPool, user_id: Uuid) -> i32 {
    sqlx::query_scalar::<_, i32>(
        r#"
        SELECT failed_login_attempts FROM users WHERE id = $1
        "#,
    )
    .bind(user_id)
    .fetch_one(pool)
    .await
    .unwrap_or(0)
}

/// Get user's lock status
pub async fn get_user_lock_status(pool: &PgPool, user_id: Uuid) -> Option<chrono::DateTime<Utc>> {
    sqlx::query_scalar::<_, Option<chrono::DateTime<Utc>>>(
        r#"
        SELECT locked_until FROM users WHERE id = $1
        "#,
    )
    .bind(user_id)
    .fetch_one(pool)
    .await
    .ok()
    .flatten()
}

// ============================================
// Redis Test Helpers
// ============================================

/// Create a test Redis connection manager
pub async fn create_test_redis() -> redis::aio::ConnectionManager {
    let redis_url =
        std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://localhost:6379".to_string());

    eprintln!("[tests] Connecting to Redis at {}", redis_url);

    let client = redis::Client::open(redis_url.clone()).expect("Failed to create Redis client");

    // 简单重试，适配容器启动延迟
    let mut last_err: Option<redis::RedisError> = None;
    for attempt in 1..=30u32 {
        // 固定 1 秒间隔，最多 30 秒
        let backoff = Duration::from_secs(1);

        match redis::aio::ConnectionManager::new(client.clone()).await {
            Ok(mut conn) => {
                // 健康检查：确保 Redis 真正就绪（能执行命令）
                match redis::cmd("PING").query_async::<_, String>(&mut conn).await {
                    Ok(_) => {
                        eprintln!("[tests] Redis ready after {} attempts", attempt);
                        return conn;
                    }
                    Err(e) => {
                        eprintln!(
                            "[tests] Redis connected but not ready (attempt {}): {}",
                            attempt, e
                        );
                        last_err = Some(e);
                        tokio::time::sleep(backoff).await;
                        continue;
                    }
                }
            }
            Err(e) => {
                last_err = Some(e);
                eprintln!(
                    "[tests] waiting for Redis (attempt {}/30): {:?}",
                    attempt, backoff
                );
                tokio::time::sleep(backoff).await;
            }
        }
    }

    panic!(
        "Failed to connect to Redis after 30 retries (30 seconds): {}",
        last_err.unwrap()
    );
}

/// Clear all Redis keys (for test isolation)
pub async fn clear_redis(redis: &mut redis::aio::ConnectionManager) {
    use redis::AsyncCommands;
    let _: Result<(), redis::RedisError> = redis.del("*").await;
}

// ============================================
// Performance Testing Helpers
// ============================================

/// Calculate percentile from sorted durations
pub fn calculate_percentile(
    mut durations: Vec<std::time::Duration>,
    percentile: f64,
) -> std::time::Duration {
    if durations.is_empty() {
        return std::time::Duration::from_secs(0);
    }

    durations.sort();
    let index = ((percentile / 100.0) * durations.len() as f64).ceil() as usize - 1;
    durations[index.min(durations.len() - 1)]
}

/// Statistics for performance testing
#[derive(Debug)]
pub struct PerformanceStats {
    pub total_requests: usize,
    pub successful: usize,
    pub failed: usize,
    pub p50: std::time::Duration,
    pub p95: std::time::Duration,
    pub p99: std::time::Duration,
    pub min: std::time::Duration,
    pub max: std::time::Duration,
    pub avg: std::time::Duration,
}

impl PerformanceStats {
    pub fn from_durations(durations: Vec<std::time::Duration>, failed_count: usize) -> Self {
        if durations.is_empty() {
            return Self {
                total_requests: failed_count,
                successful: 0,
                failed: failed_count,
                p50: std::time::Duration::from_secs(0),
                p95: std::time::Duration::from_secs(0),
                p99: std::time::Duration::from_secs(0),
                min: std::time::Duration::from_secs(0),
                max: std::time::Duration::from_secs(0),
                avg: std::time::Duration::from_secs(0),
            };
        }

        let mut sorted = durations.clone();
        sorted.sort();

        let total = durations.len();
        let sum: std::time::Duration = durations.iter().sum();
        let avg = sum / total as u32;

        Self {
            total_requests: total + failed_count,
            successful: total,
            failed: failed_count,
            p50: calculate_percentile(sorted.clone(), 50.0),
            p95: calculate_percentile(sorted.clone(), 95.0),
            p99: calculate_percentile(sorted.clone(), 99.0),
            min: sorted.first().copied().unwrap(),
            max: sorted.last().copied().unwrap(),
            avg,
        }
    }

    pub fn print_report(&self) {
        println!("\n=== Performance Test Results ===");
        println!("Total Requests:    {}", self.total_requests);
        println!("Successful:        {}", self.successful);
        println!("Failed:            {}", self.failed);
        println!(
            "Success Rate:      {:.2}%",
            (self.successful as f64 / self.total_requests as f64) * 100.0
        );
        println!("\nLatency Statistics:");
        println!("  Min:     {:?}", self.min);
        println!("  Average: {:?}", self.avg);
        println!("  P50:     {:?}", self.p50);
        println!("  P95:     {:?}", self.p95);
        println!("  P99:     {:?}", self.p99);
        println!("  Max:     {:?}", self.max);
        println!("================================\n");
    }
}
