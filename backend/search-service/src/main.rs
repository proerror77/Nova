use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::{IntoResponse, Json},
    routing::{get, post},
    Router,
};
use redis::aio::ConnectionManager;
use serde::{Deserialize, Serialize};
use sqlx::{postgres::PgPoolOptions, PgPool};
use std::net::SocketAddr;
use tokio::net::TcpListener;
use uuid::Uuid;

// ============================================
// Configuration & Error Types
// ============================================

#[derive(Debug, thiserror::Error)]
enum AppError {
    #[error("Database error: {0}")]
    Database(#[from] sqlx::Error),
    #[error("Configuration error: {0}")]
    Config(String),
    #[error("Redis error: {0}")]
    Redis(#[from] redis::RedisError),
    #[error("Serialization error: {0}")]
    Serialization(#[from] serde_json::Error),
}

impl IntoResponse for AppError {
    fn into_response(self) -> axum::response::Response {
        let (status, message) = match self {
            AppError::Database(e) => (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
            AppError::Config(e) => (StatusCode::INTERNAL_SERVER_ERROR, e),
            AppError::Redis(e) => (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
            AppError::Serialization(e) => (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
        };
        (status, Json(serde_json::json!({ "error": message }))).into_response()
    }
}

// ============================================
// Request/Response Models
// ============================================

#[derive(Debug, Deserialize)]
struct SearchParams {
    #[serde(default)]
    q: String,
    #[serde(default = "default_limit")]
    limit: i64,
}

fn default_limit() -> i64 {
    20
}

#[derive(Debug, Serialize, sqlx::FromRow)]
struct UserResult {
    id: Uuid,
    username: String,
    email: String,
    #[sqlx(default)]
    created_at: Option<chrono::DateTime<chrono::Utc>>,
}

#[derive(Debug, Serialize, Deserialize, sqlx::FromRow)]
struct PostResult {
    id: Uuid,
    user_id: Uuid,
    caption: Option<String>,
    #[sqlx(default)]
    created_at: Option<chrono::DateTime<chrono::Utc>>,
}

#[derive(Debug, Serialize)]
struct HashtagResult {
    tag: String,
    count: i64,
}

#[derive(Debug, Serialize)]
struct SearchResponse<T> {
    query: String,
    results: Vec<T>,
    count: usize,
}

// ============================================
// Application State
// ============================================

#[derive(Clone)]
struct AppState {
    db: PgPool,
    redis: ConnectionManager,
}

// ============================================
// Route Handlers
// ============================================

async fn health_handler() -> &'static str {
    "OK"
}

async fn search_users(
    State(state): State<AppState>,
    Query(params): Query<SearchParams>,
) -> Result<Json<SearchResponse<UserResult>>, AppError> {
    let search_pattern = format!("%{}%", params.q);

    let users = sqlx::query_as::<_, UserResult>(
        r#"
        SELECT id, username, email, created_at
        FROM users
        WHERE (username ILIKE $1 OR email ILIKE $1)
          AND deleted_at IS NULL
          AND is_active = true
        ORDER BY created_at DESC
        LIMIT $2
        "#,
    )
    .bind(&search_pattern)
    .bind(params.limit)
    .fetch_all(&state.db)
    .await?;

    let count = users.len();
    Ok(Json(SearchResponse {
        query: params.q,
        results: users,
        count,
    }))
}

async fn search_posts(
    State(state): State<AppState>,
    Query(params): Query<SearchParams>,
) -> Result<Json<SearchResponse<PostResult>>, AppError> {
    // Skip empty queries
    if params.q.trim().is_empty() {
        return Ok(Json(SearchResponse {
            query: params.q,
            results: vec![],
            count: 0,
        }));
    }

    let cache_key = format!("search:posts:{}", params.q);

    // Try to get from cache
    let mut redis_conn = state.redis.clone();
    if let Ok(Some(data)) = redis::cmd("GET")
        .arg(&cache_key)
        .query_async::<Option<String>>(&mut redis_conn)
        .await
    {
        if let Ok(posts) = serde_json::from_str::<Vec<PostResult>>(&data) {
            tracing::debug!("Cache hit for query: {}", params.q);
            let count = posts.len();
            return Ok(Json(SearchResponse {
                query: params.q,
                results: posts,
                count,
            }));
        }
    }

    // Cache miss - query database using full-text search
    tracing::debug!("Cache miss for query: {}", params.q);
    let posts = sqlx::query_as::<_, PostResult>(
        r#"
        SELECT id, user_id, caption, created_at
        FROM posts
        WHERE to_tsvector('english', COALESCE(caption, '')) @@
              plainto_tsquery('english', $1)
          AND soft_delete IS NULL
          AND status = 'published'
        ORDER BY ts_rank(to_tsvector('english', COALESCE(caption, '')),
                         plainto_tsquery('english', $1)) DESC,
                 created_at DESC
        LIMIT $2
        "#,
    )
    .bind(&params.q)
    .bind(params.limit)
    .fetch_all(&state.db)
    .await?;

    // Store in cache (24 hours TTL)
    if let Ok(serialized) = serde_json::to_string(&posts) {
        let _: Result<(), _> = redis::cmd("SETEX")
            .arg(&cache_key)
            .arg(86400) // 24 hours
            .arg(&serialized)
            .query_async(&mut redis_conn)
            .await;
    }

    let count = posts.len();
    Ok(Json(SearchResponse {
        query: params.q,
        results: posts,
        count,
    }))
}

async fn clear_search_cache(State(state): State<AppState>) -> Result<Json<serde_json::Value>, AppError> {
    let mut redis_conn = state.redis.clone();

    // Use SCAN to find all search:posts:* keys
    let mut cursor = 0;
    let mut deleted_count = 0;

    loop {
        let (new_cursor, keys): (i64, Vec<String>) = redis::cmd("SCAN")
            .arg(cursor)
            .arg("MATCH")
            .arg("search:posts:*")
            .arg("COUNT")
            .arg(100)
            .query_async(&mut redis_conn)
            .await?;

        if !keys.is_empty() {
            let del_count: i64 = redis::cmd("DEL")
                .arg(&keys)
                .query_async(&mut redis_conn)
                .await?;
            deleted_count += del_count;
        }

        cursor = new_cursor;
        if cursor == 0 {
            break;
        }
    }

    tracing::info!("Cleared {} cache entries", deleted_count);
    Ok(Json(serde_json::json!({
        "message": "Search cache cleared",
        "deleted_count": deleted_count
    })))
}

async fn search_hashtags(
    State(state): State<AppState>,
    Query(params): Query<SearchParams>,
) -> Result<Json<SearchResponse<HashtagResult>>, AppError> {
    // Since there's no dedicated hashtags table, we extract them from post captions
    // This is a basic implementation - in production you'd want a proper hashtags table
    let search_pattern = format!("%#{}%", params.q);

    let results = sqlx::query_as::<_, (Option<String>,)>(
        r#"
        SELECT DISTINCT caption
        FROM posts
        WHERE caption ILIKE $1
          AND soft_delete IS NULL
          AND status = 'published'
        LIMIT $2
        "#,
    )
    .bind(&search_pattern)
    .bind(params.limit)
    .fetch_all(&state.db)
    .await?;

    // Extract hashtags from captions
    let mut hashtag_map: std::collections::HashMap<String, i64> = std::collections::HashMap::new();

    for (caption,) in results {
        if let Some(text) = caption {
            // Simple hashtag extraction - matches #word
            for word in text.split_whitespace() {
                if let Some(tag) = word.strip_prefix('#') {
                    let clean_tag = tag.trim_end_matches(|c: char| !c.is_alphanumeric());
                    if !clean_tag.is_empty()
                        && clean_tag.to_lowercase().contains(&params.q.to_lowercase())
                    {
                        *hashtag_map.entry(clean_tag.to_string()).or_insert(0) += 1;
                    }
                }
            }
        }
    }

    let mut hashtags: Vec<HashtagResult> = hashtag_map
        .into_iter()
        .map(|(tag, count)| HashtagResult { tag, count })
        .collect();

    // Sort by count descending
    hashtags.sort_by(|a, b| b.count.cmp(&a.count));
    hashtags.truncate(params.limit as usize);

    let count = hashtags.len();
    Ok(Json(SearchResponse {
        query: params.q,
        results: hashtags,
        count,
    }))
}

// ============================================
// Application Setup
// ============================================

fn build_router() -> Router<AppState> {
    Router::new()
        .route("/health", get(health_handler))
        .route("/api/v1/search/users", get(search_users))
        .route("/api/v1/search/posts", get(search_posts))
        .route("/api/v1/search/hashtags", get(search_hashtags))
        .route("/api/v1/search/clear-cache", post(clear_search_cache))
}

async fn init_db_pool(database_url: &str) -> Result<PgPool, sqlx::Error> {
    PgPoolOptions::new()
        .max_connections(10)
        .connect(database_url)
        .await
}

async fn init_redis_connection(redis_url: &str) -> Result<ConnectionManager, redis::RedisError> {
    let client = redis::Client::open(redis_url)?;
    ConnectionManager::new(client).await
}

// ============================================
// Main Entry Point
// ============================================

#[tokio::main]
async fn main() -> Result<(), AppError> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "search_service=debug,tower_http=debug".into()),
        )
        .init();

    // Load environment variables
    dotenvy::dotenv().ok();

    // Get configuration from environment
    let database_url = std::env::var("DATABASE_URL")
        .map_err(|_| AppError::Config("DATABASE_URL must be set".to_string()))?;

    let redis_url = std::env::var("REDIS_URL")
        .unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());

    let port: u16 = std::env::var("PORT")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(8081);

    // Initialize database connection pool
    tracing::info!("Connecting to database...");
    let db = init_db_pool(&database_url)
        .await
        .map_err(|e| AppError::Config(format!("Failed to connect to database: {e}")))?;

    tracing::info!("Database connection established");

    // Initialize Redis connection
    tracing::info!("Connecting to Redis at {}...", redis_url);
    let redis = init_redis_connection(&redis_url)
        .await
        .map_err(|e| AppError::Config(format!("Failed to connect to Redis: {e}")))?;

    tracing::info!("Redis connection established");

    // Create application state
    let state = AppState { db, redis };

    // Build router with state
    let app = build_router().with_state(state);

    // Start server
    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    tracing::info!("search-service listening on {}", addr);

    let listener = TcpListener::bind(addr)
        .await
        .map_err(|e| AppError::Config(format!("Failed to bind to {addr}: {e}")))?;

    axum::serve(listener, app)
        .await
        .map_err(|e| AppError::Config(format!("Server error: {e}")))?;

    Ok(())
}
