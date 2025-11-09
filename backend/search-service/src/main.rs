use actix_middleware::MetricsMiddleware;
use actix_web::{
    web::{self, Data, Json, Query},
    App, HttpResponse, HttpServer, Responder,
};
use error_types::ErrorResponse;
use redis::aio::ConnectionManager;
use search_service::events::consumers::EventContext;
use search_service::events::kafka::{spawn_message_consumer, KafkaConsumerConfig};
use search_service::events::SearchIndexConsumer;
use search_service::openapi::ApiDoc;
use search_service::search_suggestions::SearchSuggestionsService;
use search_service::services::elasticsearch::{
    ElasticsearchClient, ElasticsearchError, PostDocument,
};
use search_service::services::{ClickHouseClient, RedisCache};
use serde::{Deserialize, Serialize};
use sqlx::{postgres::PgPoolOptions, PgPool};
use std::sync::Arc;
use tonic::transport::Server as GrpcServer;
use tonic_health::server::health_reporter;
use utoipa::OpenApi;
use utoipa_swagger_ui::SwaggerUi;
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

impl actix_web::ResponseError for AppError {
    fn error_response(&self) -> HttpResponse {
        let (status, error_type, code) = match &self {
            AppError::Database(_) => (
                actix_web::http::StatusCode::INTERNAL_SERVER_ERROR,
                "server_error",
                error_types::error_codes::DATABASE_ERROR,
            ),
            AppError::Config(_) => (
                actix_web::http::StatusCode::INTERNAL_SERVER_ERROR,
                "server_error",
                error_types::error_codes::INTERNAL_SERVER_ERROR,
            ),
            AppError::Redis(_) => (
                actix_web::http::StatusCode::INTERNAL_SERVER_ERROR,
                "server_error",
                error_types::error_codes::CACHE_ERROR,
            ),
            AppError::Serialization(_) => (
                actix_web::http::StatusCode::INTERNAL_SERVER_ERROR,
                "server_error",
                error_types::error_codes::INTERNAL_SERVER_ERROR,
            ),
            AppError::SearchBackend(_) => (
                actix_web::http::StatusCode::BAD_GATEWAY,
                "server_error",
                error_types::error_codes::SERVICE_UNAVAILABLE,
            ),
        };

        let message = self.to_string();
        let response = ErrorResponse::new(
            &match status {
                actix_web::http::StatusCode::BAD_REQUEST => "Bad Request",
                actix_web::http::StatusCode::INTERNAL_SERVER_ERROR => "Internal Server Error",
                actix_web::http::StatusCode::BAD_GATEWAY => "Bad Gateway",
                _ => "Error",
            },
            &message,
            status.as_u16(),
            error_type,
            code,
        );

        HttpResponse::build(status).json(response)
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
    #[serde(default)]
    offset: i64,
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
            caption: doc.content,
            created_at: Some(doc.created_at),
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

async fn health_handler() -> impl Responder {
    "OK"
}

async fn search_users(
    state: Data<AppState>,
    params: Query<SearchParams>,
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
        query: params.q.clone(),
        results: users,
        count,
    }))
}

async fn search_posts(
    state: Data<AppState>,
    params: Query<SearchParams>,
) -> Result<Json<SearchResponse<PostResult>>, AppError> {
    // Skip empty queries
    if params.q.trim().is_empty() {
        return Ok(Json(SearchResponse {
            query: params.q.clone(),
            results: vec![],
            count: 0,
        }));
    }

    if let Some(search_backend) = &state.search_backend {
        match search_backend
            .search_posts(&params.q, params.limit, params.offset)
            .await
        {
            Ok(documents) => {
                let posts: Vec<PostResult> = documents.into_iter().map(PostResult::from).collect();
                let count = posts.len();
                return Ok(Json(SearchResponse {
                    query: params.q.clone(),
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
                query: params.q.clone(),
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
        query: params.q.clone(),
        results: posts,
        count,
    }))
}

async fn clear_search_cache(state: Data<AppState>) -> Result<Json<serde_json::Value>, AppError> {
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
    state: Data<AppState>,
    payload: Json<ReindexRequest>,
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
            title: None,
            content: post.caption.clone(),
            tags: vec![],
            likes_count: 0,
            comments_count: 0,
            created_at: post.created_at.unwrap_or(chrono::Utc::now()),
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
    state: Data<AppState>,
    params: Query<SuggestionsParams>,
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
    state: Data<AppState>,
    params: Query<SearchParams>,
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
    state: Data<AppState>,
    params: Json<RecordClickParams>,
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
    state: Data<AppState>,
    params: Query<SearchParams>,
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
        query: params.q.clone(),
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
    state: Data<AppState>,
    params: Query<UnifiedSearchParams>,
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
        query: params.q.clone(),
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
async fn openapi_json(doc: Data<utoipa::openapi::OpenApi>) -> actix_web::Result<HttpResponse> {
    let body = serde_json::to_string(&*doc).map_err(|e| {
        tracing::error!("OpenAPI serialization failed: {}", e);
        actix_web::error::ErrorInternalServerError("OpenAPI serialization error")
    })?;

    Ok(HttpResponse::Ok()
        .content_type("application/json")
        .body(body))
}

// Documentation entry point
async fn docs() -> impl Responder {
    HttpResponse::Ok()
        .content_type("text/html; charset=utf-8")
        .body(
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
        <a href="/swagger-ui/">📘 Swagger UI (Interactive)</a>
        <a href="/api/v1/openapi.json">📄 OpenAPI JSON (Raw)</a>
    </div>
</body>
</html>"#,
        )
}

async fn init_db_pool(database_url: &str) -> Result<PgPool, sqlx::Error> {
    let mut cfg = db_pool::DbConfig::for_service("search-service");
    if cfg.database_url.is_empty() {
        cfg.database_url = database_url.to_string();
    }
    if cfg.max_connections < 20 {
        cfg.max_connections = 20;
    }
    db_pool::create_pool(cfg).await
}

async fn init_redis_connection(redis_url: &str) -> Result<ConnectionManager, redis::RedisError> {
    let client = redis::Client::open(redis_url)?;
    ConnectionManager::new(client).await
}

// ============================================
// Main Entry Point
// ============================================

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "search_service=debug,actix_web=debug".into()),
        )
        .init();

    // Load environment variables
    dotenvy::dotenv().ok();

    // Get configuration from environment
    let database_url = match std::env::var("DATABASE_URL") {
        Ok(url) => url,
        Err(e) => {
            tracing::error!("DATABASE_URL environment variable not set: {:#}", e);
            eprintln!("ERROR: DATABASE_URL must be set");
            std::process::exit(1);
        }
    };

    let redis_url =
        std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());

    let port: u16 = std::env::var("PORT")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(8081);

    // Initialize database connection pool
    tracing::info!("Connecting to database...");
    let db = match init_db_pool(&database_url).await {
        Ok(pool) => pool,
        Err(e) => {
            tracing::error!("Database pool creation failed: {:#}", e);
            eprintln!("ERROR: Failed to connect to database: {}", e);
            std::process::exit(1);
        }
    };

    tracing::info!("Database connection established");

    // Initialize Redis connection
    tracing::info!("Connecting to Redis at {}...", redis_url);
    let redis = match init_redis_connection(&redis_url).await {
        Ok(conn) => conn,
        Err(e) => {
            tracing::error!("Redis connection failed: {:#}", e);
            eprintln!("ERROR: Failed to connect to Redis: {}", e);
            std::process::exit(1);
        }
    };

    tracing::info!("Redis connection established");

    // Initialize ClickHouse client
    let clickhouse_url =
        std::env::var("CLICKHOUSE_URL").unwrap_or_else(|_| "http://localhost:8123".to_string());
    let ch_client = match ClickHouseClient::new(&clickhouse_url).await {
        Ok(client) => {
            tracing::info!("ClickHouse connected: {}", clickhouse_url);
            Some(Arc::new(client))
        }
        Err(err) => {
            tracing::warn!("Failed to initialize ClickHouse client: {}", err);
            None
        }
    };

    // Initialize Redis cache
    let redis_cache = match RedisCache::new(&redis_url, 3600).await {
        Ok(cache) => {
            tracing::info!("Redis cache initialized");
            Some(Arc::new(cache))
        }
        Err(err) => {
            tracing::warn!("Failed to initialize Redis cache: {}", err);
            None
        }
    };

    // Create application state
    let search_backend = match std::env::var("ELASTICSEARCH_URL") {
        Ok(url) if !url.is_empty() => {
            let post_index = std::env::var("ELASTICSEARCH_POST_INDEX")
                .unwrap_or_else(|_| "nova_posts".to_string());
            let message_index = std::env::var("ELASTICSEARCH_MESSAGE_INDEX")
                .unwrap_or_else(|_| "nova_messages".to_string());
            let user_index = std::env::var("ELASTICSEARCH_USER_INDEX")
                .unwrap_or_else(|_| "nova_users".to_string());
            let comment_index = std::env::var("ELASTICSEARCH_COMMENT_INDEX")
                .unwrap_or_else(|_| "nova_comments".to_string());

            match ElasticsearchClient::new(
                &url,
                &post_index,
                &message_index,
                &user_index,
                &comment_index,
            )
            .await
            {
                Ok(client) => {
                    tracing::info!(
                        "Elasticsearch enabled: post={}, message={}, user={}, comment={}",
                        post_index,
                        message_index,
                        user_index,
                        comment_index
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

    // Clone clients for gRPC service before moving into state
    let grpc_es = search_backend.clone();
    let grpc_ch = ch_client.clone();
    let grpc_redis = redis_cache.clone();

    let state = AppState {
        db,
        redis,
        search_backend,
    };

    let state_data = Data::new(state);

    // Start gRPC server on port (PORT + 1000) with all clients
    let grpc_addr: std::net::SocketAddr = format!("0.0.0.0:{}", port + 1000)
        .parse()
        .expect("Invalid gRPC bind address");

    tokio::spawn(async move {
        let (mut health, health_service) = health_reporter();
        // Mark SearchService as serving
        health
            .set_serving::<search_service::grpc::nova::search_service::v1::search_service_server::SearchServiceServer<search_service::grpc::SearchServiceImpl>>()
            .await;

        // Create gRPC service with clients (only if all are available)
        let svc = if let (Some(es), Some(ch), Some(redis)) = (grpc_es, grpc_ch, grpc_redis) {
            let es = Arc::try_unwrap(es).unwrap_or_else(|arc| (*arc).clone());
            let ch = Arc::try_unwrap(ch).unwrap_or_else(|arc| (*arc).clone());
            let redis = Arc::try_unwrap(redis).unwrap_or_else(|arc| (*arc).clone());
            Some(search_service::grpc::SearchServiceImpl::new(es, ch, redis))
        } else {
            tracing::error!(
                "Cannot start gRPC service: missing required clients (ES/ClickHouse/Redis)"
            );
            None
        };

        if let Some(svc) = svc {
            if let Err(e) = GrpcServer::builder()
                .add_service(health_service)
                .add_service(search_service::grpc::nova::search_service::v1::search_service_server::SearchServiceServer::new(svc))
                .serve(grpc_addr)
                .await
            {
                tracing::error!("search-service gRPC server error: {}", e);
            }
        } else {
            tracing::error!("gRPC server not started: missing clients");
        }
    });

    // Start server
    tracing::info!("search-service listening on 0.0.0.0:{}", port);

    HttpServer::new(move || {
        let openapi_doc = ApiDoc::openapi();

        App::new()
            .app_data(state_data.clone())
            .app_data(Data::new(openapi_doc.clone()))
            .wrap(MetricsMiddleware)
            // Health endpoint (no auth)
            .route("/health", web::get().to(health_handler))
            // Documentation endpoints (no auth)
            .service(
                SwaggerUi::new("/swagger-ui/{_:.*}")
                    .url("/api/v1/openapi.json", openapi_doc.clone()),
            )
            .route("/api/v1/openapi.json", web::get().to(openapi_json))
            .route("/openapi.json", web::get().to(openapi_json))
            .route("/docs", web::get().to(docs))
            // API endpoints (with auth middleware if needed)
            .service(
                web::scope("/api/v1/search")
                    // Unified search endpoint
                    .route("", web::get().to(unified_search))
                    // Type-specific search endpoints
                    .route("/users", web::get().to(search_users))
                    .route("/posts", web::get().to(search_posts))
                    .route("/hashtags", web::get().to(search_hashtags))
                    // Cache management
                    .route("/clear-cache", web::post().to(clear_search_cache))
                    .route("/posts/reindex", web::post().to(reindex_posts))
                    // Search suggestions and trends
                    .route("/suggestions", web::get().to(get_search_suggestions))
                    .route("/trending", web::get().to(get_trending_searches))
                    // Search analytics
                    .route("/clicks", web::post().to(record_search_click)),
            )
    })
    .bind(("0.0.0.0", port))?
    .run()
    .await
}
