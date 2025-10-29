use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::{IntoResponse, Json},
    routing::{get, post},
    Router,
};
use error_types::ErrorResponse;
use redis::aio::ConnectionManager;
use search_service::elasticsearch::{ElasticsearchClient, ElasticsearchError, PostDocument};
use search_service::events::consumers::EventContext;
use search_service::events::kafka::{spawn_message_consumer, KafkaConsumerConfig};
use search_service::search_suggestions::SearchSuggestionsService;
use serde::{Deserialize, Serialize};
use sqlx::{postgres::PgPoolOptions, PgPool};
use std::{net::SocketAddr, sync::Arc};
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
    #[error("Search backend error: {0}")]
    SearchBackend(String),
}

impl IntoResponse for AppError {
    fn into_response(self) -> axum::response::Response {
        let (status, error_type, code) = match &self {
            AppError::Database(_) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                "server_error",
                error_types::error_codes::DATABASE_ERROR,
            ),
            AppError::Config(_) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                "server_error",
                error_types::error_codes::INTERNAL_SERVER_ERROR,
            ),
            AppError::Redis(_) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                "server_error",
                error_types::error_codes::CACHE_ERROR,
            ),
            AppError::Serialization(_) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                "server_error",
                error_types::error_codes::INTERNAL_SERVER_ERROR,
            ),
            AppError::SearchBackend(_) => (
                StatusCode::BAD_GATEWAY,
                "server_error",
                error_types::error_codes::SERVICE_UNAVAILABLE,
            ),
        };

        let message = self.to_string();
        let response = ErrorResponse::new(
            &match status {
                StatusCode::BAD_REQUEST => "Bad Request",
                StatusCode::INTERNAL_SERVER_ERROR => "Internal Server Error",
                StatusCode::BAD_GATEWAY => "Bad Gateway",
                _ => "Error",
            },
            &message,
            status.as_u16(),
            error_type,
            code,
        );

        (status, Json(response)).into_response()
    }
}

impl From<ElasticsearchError> for AppError {
    fn from(err: ElasticsearchError) -> Self {
        AppError::SearchBackend(err.to_string())
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

#[derive(Debug, Deserialize)]
struct SuggestionsParams {
    query_type: String, // 'user', 'post', 'hashtag', 'video', 'stream'
    prefix: String,
    #[serde(default = "default_suggestion_limit")]
    limit: i64,
}

fn default_suggestion_limit() -> i64 {
    10
}

#[derive(Debug, Deserialize)]
struct RecordClickParams {
    query_type: String,
    query_text: String,
    result_id: Uuid,
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

impl From<PostDocument> for PostResult {
    fn from(doc: PostDocument) -> Self {
        Self {
            id: doc.id,
            user_id: doc.user_id,
            caption: doc.caption,
            created_at: doc.created_at,
        }
    }
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

#[derive(Debug, Deserialize)]
struct ReindexRequest {
    #[serde(default = "default_reindex_batch_size")]
    batch_size: i64,
    #[serde(default)]
    offset: i64,
}

fn default_reindex_batch_size() -> i64 {
    500
}

// ============================================
// Application State
// ============================================

#[derive(Clone)]
struct AppState {
    db: PgPool,
    redis: ConnectionManager,
    search_backend: Option<Arc<ElasticsearchClient>>,
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

    if let Some(search_backend) = &state.search_backend {
        match search_backend.search_posts(&params.q, params.limit).await {
            Ok(documents) => {
                let posts: Vec<PostResult> = documents.into_iter().map(PostResult::from).collect();
                let count = posts.len();
                return Ok(Json(SearchResponse {
                    query: params.q,
                    results: posts,
                    count,
                }));
            }
            Err(err) => {
                tracing::warn!("Elasticsearch search failed for '{}': {}", params.q, err);
            }
        }
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

async fn clear_search_cache(
    State(state): State<AppState>,
) -> Result<Json<serde_json::Value>, AppError> {
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

async fn reindex_posts(
    State(state): State<AppState>,
    Json(payload): Json<ReindexRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    let search_backend = state
        .search_backend
        .clone()
        .ok_or_else(|| AppError::Config("Elasticsearch backend disabled".into()))?;

    let limit = payload.batch_size.clamp(1, 1_000);
    let offset = payload.offset.max(0);

    let posts = sqlx::query_as::<_, PostResult>(
        r#"
        SELECT id, user_id, caption, created_at
        FROM posts
        WHERE soft_delete IS NULL
          AND status = 'published'
        ORDER BY created_at DESC
        LIMIT $1 OFFSET $2
        "#,
    )
    .bind(limit)
    .bind(offset)
    .fetch_all(&state.db)
    .await?;

    for post in &posts {
        let doc = PostDocument {
            id: post.id,
            user_id: post.user_id,
            caption: post.caption.clone(),
            created_at: post.created_at,
        };
        search_backend.index_post(&doc).await?;
    }

    Ok(Json(serde_json::json!({
        "message": "Reindex completed",
        "indexed_count": posts.len(),
        "batch_size": limit,
        "offset": offset,
    })))
}

async fn get_search_suggestions(
    State(state): State<AppState>,
    Query(params): Query<SuggestionsParams>,
) -> Result<Json<serde_json::Value>, AppError> {
    // For authenticated users, we'd get user_id from JWT
    // For now, we return global suggestions
    let result = SearchSuggestionsService::get_suggestions(
        &state.db,
        None, // user_id - would come from JWT in production
        &params.query_type,
        &params.prefix,
        params.limit,
    )
    .await
    .map_err(|e| AppError::Config(e))?;

    Ok(Json(serde_json::json!({
        "query_type": params.query_type,
        "prefix": params.prefix,
        "suggestions": result.suggestions,
        "total": result.total
    })))
}

async fn get_trending_searches(
    State(state): State<AppState>,
    Query(params): Query<SearchParams>,
) -> Result<Json<serde_json::Value>, AppError> {
    let query_type = params.q.clone();
    let trending = SearchSuggestionsService::get_trending_searches(&state.db, &query_type, 20)
        .await
        .map_err(|e| AppError::Config(e))?;

    Ok(Json(serde_json::json!({
        "query_type": query_type,
        "trending": trending,
        "count": trending.len()
    })))
}

async fn record_search_click(
    State(state): State<AppState>,
    Json(params): Json<RecordClickParams>,
) -> Result<Json<serde_json::Value>, AppError> {
    // In production, user_id would come from JWT
    let user_id = Uuid::nil(); // Placeholder

    SearchSuggestionsService::record_click(
        &state.db,
        user_id,
        &params.query_type,
        &params.query_text,
        params.result_id,
    )
    .await
    .map_err(|e| AppError::Config(e))?;

    Ok(Json(serde_json::json!({
        "message": "Click recorded successfully"
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

#[derive(Debug, Deserialize)]
struct UnifiedSearchParams {
    q: String,
    #[serde(default = "default_search_types")]
    types: String, // Comma-separated: 'user', 'post', 'hashtag'
    #[serde(default = "default_limit")]
    limit: i64,
}

fn default_search_types() -> String {
    "user,post,hashtag".to_string()
}

#[derive(Debug, Serialize)]
struct UnifiedSearchResult {
    query: String,
    users: Vec<UserResult>,
    posts: Vec<PostResult>,
    hashtags: Vec<HashtagResult>,
    total_results: usize,
}

/// Unified search endpoint supporting multiple types
async fn unified_search(
    State(state): State<AppState>,
    Query(params): Query<UnifiedSearchParams>,
) -> Result<Json<UnifiedSearchResult>, AppError> {
    let mut users = vec![];
    let mut posts = vec![];
    let mut hashtags = vec![];

    let search_types: Vec<&str> = params.types.split(',').map(|s| s.trim()).collect();

    // Search users if requested
    if search_types.contains(&"user") {
        let search_pattern = format!("%{}%", params.q);
        users = sqlx::query_as::<_, UserResult>(
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
    }

    // Search posts if requested
    if search_types.contains(&"post") {
        if !params.q.trim().is_empty() {
            posts = sqlx::query_as::<_, PostResult>(
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
        }
    }

    // Search hashtags if requested
    if search_types.contains(&"hashtag") {
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

        let mut hashtag_map: std::collections::HashMap<String, i64> =
            std::collections::HashMap::new();
        for (caption,) in results {
            if let Some(text) = caption {
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

        hashtags = hashtag_map
            .into_iter()
            .map(|(tag, count)| HashtagResult { tag, count })
            .collect();
        hashtags.sort_by(|a, b| b.count.cmp(&a.count));
        hashtags.truncate(params.limit as usize);
    }

    let total_results = users.len() + posts.len() + hashtags.len();

    Ok(Json(UnifiedSearchResult {
        query: params.q,
        users,
        posts,
        hashtags,
        total_results,
    }))
}

// ============================================
// Application Setup
// ============================================

// OpenAPI endpoint handler
async fn openapi_json() -> axum::Json<serde_json::Value> {
    use utoipa::OpenApi;
    axum::Json(serde_json::to_value(&search_service::openapi::ApiDoc::openapi()).unwrap())
}

// Swagger UI handler
async fn swagger_ui() -> axum::response::Html<&'static str> {
    axum::response::Html(
        r#"<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Nova Search Service API</title>
    <link rel="stylesheet" type="text/css" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css" />
</head>
<body>
    <div id="swagger-ui"></div>
    <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
    <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-standalone-preset.js"></script>
    <script>
        window.onload = function() {
            SwaggerUIBundle({
                url: "/openapi.json",
                dom_id: '#swagger-ui',
                deepLinking: true,
                presets: [
                    SwaggerUIBundle.presets.apis,
                    SwaggerUIStandalonePreset
                ],
                plugins: [
                    SwaggerUIBundle.plugins.DownloadUrl
                ],
                layout: "StandaloneLayout"
            });
        };
    </script>
</body>
</html>"#,
    )
}

// Documentation entry point
async fn docs() -> axum::response::Html<&'static str> {
    axum::response::Html(
        r#"<!DOCTYPE html>
<html>
<head>
    <title>Nova Search Service API</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { max-width: 600px; margin: 0 auto; background: white; padding: 40px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; }
        a { display: block; margin: 15px 0; padding: 15px; background: #dc3545; color: white; text-decoration: none; border-radius: 4px; }
        a:hover { background: #c82333; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Nova Search Service API</h1>
        <p>Choose your preferred documentation viewer:</p>
        <a href="/swagger-ui">📘 Swagger UI (Interactive)</a>
        <a href="/openapi.json">📄 OpenAPI JSON (Raw)</a>
    </div>
</body>
</html>"#,
    )
}

fn build_router() -> Router<AppState> {
    Router::new()
        .route("/health", get(health_handler))
        .route("/openapi.json", get(openapi_json))
        .route("/swagger-ui", get(swagger_ui))
        .route("/docs", get(docs))
        // Unified search endpoint
        .route("/api/v1/search", get(unified_search))
        // Type-specific search endpoints
        .route("/api/v1/search/users", get(search_users))
        .route("/api/v1/search/posts", get(search_posts))
        .route("/api/v1/search/hashtags", get(search_hashtags))
        // Cache management
        .route("/api/v1/search/clear-cache", post(clear_search_cache))
        .route("/api/v1/search/posts/reindex", post(reindex_posts))
        // Search suggestions and trends
        .route("/api/v1/search/suggestions", get(get_search_suggestions))
        .route("/api/v1/search/trending", get(get_trending_searches))
        // Search analytics
        .route("/api/v1/search/clicks", post(record_search_click))
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

    let redis_url =
        std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());

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
    let search_backend = match std::env::var("ELASTICSEARCH_URL") {
        Ok(url) if !url.is_empty() => {
            let index_name = std::env::var("ELASTICSEARCH_POST_INDEX")
                .unwrap_or_else(|_| "nova_posts".to_string());
            let message_index = std::env::var("ELASTICSEARCH_MESSAGE_INDEX")
                .unwrap_or_else(|_| "nova_messages".to_string());
            match ElasticsearchClient::new(&url, &index_name, &message_index).await {
                Ok(client) => {
                    tracing::info!(
                        "Elasticsearch enabled: post_index={}, message_index={}",
                        index_name,
                        message_index
                    );
                    Some(Arc::new(client))
                }
                Err(err) => {
                    tracing::warn!("Failed to initialize Elasticsearch client: {}", err);
                    None
                }
            }
        }
        _ => {
            tracing::info!(
                "Elasticsearch URL not set. Falling back to PostgreSQL full-text search"
            );
            None
        }
    };

    if let Some(search_backend_clone) = search_backend.clone() {
        if let Some(kafka_config) = KafkaConsumerConfig::from_env() {
            let ctx = EventContext::new(Some(search_backend_clone));
            spawn_message_consumer(ctx, kafka_config);
        } else {
            tracing::info!("Kafka configuration missing; skipping message indexing consumer");
        }
    } else {
        tracing::info!("Search backend disabled; Kafka consumer not started");
    }

    let state = AppState {
        db,
        redis,
        search_backend,
    };

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
