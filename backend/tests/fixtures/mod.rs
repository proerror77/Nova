pub mod assertions;
/// Test fixtures and utilities for integration tests
/// Provides database setup, test data creation, and cleanup
// Phase 1B 集成测试基础设施
pub mod test_env;

use chrono::{DateTime, Utc};
use sqlx::{FromRow, PgPool, Postgres, Transaction};
use uuid::Uuid;

// ============================================
// Test Models (simplified versions)
// ============================================

#[derive(Debug, Clone, FromRow)]
pub struct User {
    pub id: Uuid,
    pub email: String,
    pub username: String,
    pub password_hash: String,
    pub email_verified: bool,
    pub is_active: bool,
    pub failed_login_attempts: i32,
    pub locked_until: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub last_login_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, FromRow)]
pub struct Post {
    pub id: Uuid,
    pub user_id: Uuid,
    pub caption: Option<String>,
    pub image_key: String,
    pub image_sizes: Option<sqlx::types::Json<serde_json::Value>>,
    pub status: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub soft_delete: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, FromRow)]
pub struct PostImage {
    pub id: Uuid,
    pub post_id: Uuid,
    pub s3_key: String,
    pub status: String,
    pub size_variant: String,
    pub file_size: Option<i64>,
    pub width: Option<i32>,
    pub height: Option<i32>,
    pub url: Option<String>,
    pub error_message: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, FromRow)]
pub struct PostMetadata {
    pub post_id: Uuid,
    pub like_count: i32,
    pub comment_count: i32,
    pub view_count: i32,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

// ============================================
// Database Setup
// ============================================

/// Create a test database pool with migrations
pub async fn create_test_pool() -> PgPool {
    let database_url = std::env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgres://postgres:postgres@localhost:5432/nova_test".to_string());

    let pool = sqlx::PgPool::connect(&database_url)
        .await
        .expect("Failed to connect to test database");

    // Run migrations (path relative to workspace root)
    sqlx::migrate!("backend/migrations")
        .run(&pool)
        .await
        .expect("Failed to run migrations");

    pool
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
        let caption_text = format!("Test post {}", i + 1);
        let caption = Some(caption_text.as_str());
        let post = create_test_post_with_caption(pool, user_id, caption, "published").await;
        posts.push(post);

        // Small delay to ensure different timestamps
        tokio::time::sleep(tokio::time::Duration::from_millis(10)).await;
    }

    posts
}
