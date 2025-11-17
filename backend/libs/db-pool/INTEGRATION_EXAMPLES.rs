// Pool Exhaustion Backpressure - Integration Examples
// Copy relevant code snippets to your service

//==============================================================================
// Example 1: user-service (gRPC + Tonic)
//==============================================================================

mod user_service_example {
    use db_pool::{acquire_with_backpressure, BackpressureConfig, PoolExhaustedError};
    use sqlx::PgPool;
    use tonic::{Code, Request, Response, Status};

    #[derive(Clone)]
    pub struct UserServiceImpl {
        pool: PgPool,
        backpressure_config: BackpressureConfig,
    }

    impl UserServiceImpl {
        pub fn new(pool: PgPool) -> Self {
            Self {
                pool,
                backpressure_config: BackpressureConfig::from_env(),
            }
        }

        /// Example gRPC method with backpressure
        pub async fn get_user_with_backpressure(
            &self,
            user_id: i64,
        ) -> Result<User, Status> {
            // Acquire connection with backpressure
            let mut conn = acquire_with_backpressure(
                &self.pool,
                "user-service",
                self.backpressure_config,
            )
            .await
            .map_err(|e| {
                // Pool exhausted - return UNAVAILABLE immediately
                tracing::warn!(
                    user_id = %user_id,
                    error = %e,
                    "Pool exhausted, rejecting get_user request"
                );
                Status::new(
                    Code::Unavailable,
                    format!("Service temporarily overloaded: {}", e),
                )
            })?;

            // Use connection normally
            let user = sqlx::query_as::<_, User>("SELECT * FROM users WHERE id = $1")
                .bind(user_id)
                .fetch_one(&mut *conn)
                .await
                .map_err(|e| {
                    tracing::error!(error = %e, "Database query failed");
                    Status::internal(e.to_string())
                })?;

            Ok(user)
        }

        /// Example: Create user with backpressure
        pub async fn create_user_with_backpressure(
            &self,
            req: CreateUserRequest,
        ) -> Result<User, Status> {
            let mut conn = acquire_with_backpressure(
                &self.pool,
                "user-service",
                self.backpressure_config,
            )
            .await
            .map_err(|e| Status::unavailable(format!("Service overloaded: {}", e)))?;

            let user = sqlx::query_as::<_, User>(
                "INSERT INTO users (username, email) VALUES ($1, $2) RETURNING *",
            )
            .bind(&req.username)
            .bind(&req.email)
            .fetch_one(&mut *conn)
            .await
            .map_err(|e| Status::internal(e.to_string()))?;

            Ok(user)
        }
    }

    // Stub types for compilation
    #[derive(Debug)]
    pub struct User {
        pub id: i64,
        pub username: String,
        pub email: String,
    }

    #[derive(Debug)]
    pub struct CreateUserRequest {
        pub username: String,
        pub email: String,
    }
}

//==============================================================================
// Example 2: feed-service (REST + Axum)
//==============================================================================

mod feed_service_example {
    use axum::{
        extract::{Query, State},
        http::StatusCode,
        response::IntoResponse,
        Json, Router,
    };
    use db_pool::{acquire_with_backpressure, BackpressureConfig, PoolExhaustedError};
    use serde::{Deserialize, Serialize};
    use sqlx::PgPool;
    use std::sync::Arc;

    #[derive(Clone)]
    pub struct AppState {
        pool: PgPool,
        backpressure_config: BackpressureConfig,
    }

    impl AppState {
        pub fn new(pool: PgPool) -> Self {
            Self {
                pool,
                backpressure_config: BackpressureConfig::from_env(),
            }
        }
    }

    #[derive(Deserialize)]
    pub struct GetFeedQuery {
        user_id: i64,
        limit: Option<i64>,
    }

    #[derive(Serialize)]
    pub struct GetFeedResponse {
        posts: Vec<Post>,
        has_more: bool,
    }

    /// Example REST endpoint with backpressure
    pub async fn get_feed(
        State(state): State<Arc<AppState>>,
        Query(query): Query<GetFeedQuery>,
    ) -> Result<Json<GetFeedResponse>, (StatusCode, String)> {
        // Acquire connection with backpressure
        let mut conn = acquire_with_backpressure(
            &state.pool,
            "feed-service",
            state.backpressure_config,
        )
        .await
        .map_err(|e| {
            // Pool exhausted - return 503 Service Unavailable
            tracing::warn!(
                user_id = %query.user_id,
                error = %e,
                "Pool exhausted, rejecting get_feed request"
            );
            (
                StatusCode::SERVICE_UNAVAILABLE,
                format!("Service temporarily overloaded: {}", e),
            )
        })?;

        let limit = query.limit.unwrap_or(20).min(100);

        // Use connection normally
        let posts = sqlx::query_as::<_, Post>(
            "SELECT * FROM posts WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2",
        )
        .bind(query.user_id)
        .bind(limit)
        .fetch_all(&mut *conn)
        .await
        .map_err(|e| {
            tracing::error!(error = %e, "Database query failed");
            (StatusCode::INTERNAL_SERVER_ERROR, e.to_string())
        })?;

        let has_more = posts.len() as i64 >= limit;

        Ok(Json(GetFeedResponse { posts, has_more }))
    }

    /// Example: Create post endpoint with backpressure
    pub async fn create_post(
        State(state): State<Arc<AppState>>,
        Json(req): Json<CreatePostRequest>,
    ) -> Result<Json<Post>, (StatusCode, String)> {
        let mut conn = acquire_with_backpressure(
            &state.pool,
            "feed-service",
            state.backpressure_config,
        )
        .await
        .map_err(|e| (StatusCode::SERVICE_UNAVAILABLE, e.to_string()))?;

        let post = sqlx::query_as::<_, Post>(
            "INSERT INTO posts (user_id, content) VALUES ($1, $2) RETURNING *",
        )
        .bind(req.user_id)
        .bind(&req.content)
        .fetch_one(&mut *conn)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

        Ok(Json(post))
    }

    /// Build router with backpressure endpoints
    pub fn build_router(state: Arc<AppState>) -> Router {
        Router::new()
            .route("/feed", axum::routing::get(get_feed))
            .route("/posts", axum::routing::post(create_post))
            .with_state(state)
    }

    // Stub types
    #[derive(Debug, Serialize)]
    pub struct Post {
        pub id: i64,
        pub user_id: i64,
        pub content: String,
        pub created_at: chrono::DateTime<chrono::Utc>,
    }

    #[derive(Deserialize)]
    pub struct CreatePostRequest {
        pub user_id: i64,
        pub content: String,
    }
}

//==============================================================================
// Example 3: graphql-gateway (GraphQL + async-graphql)
//==============================================================================

mod graphql_gateway_example {
    use async_graphql::{Context, Object, Result as GqlResult, Schema};
    use db_pool::{acquire_with_backpressure, BackpressureConfig, PoolExhaustedError};
    use sqlx::PgPool;

    pub struct QueryRoot;

    #[Object]
    impl QueryRoot {
        /// Example GraphQL query with backpressure
        async fn user(&self, ctx: &Context<'_>, id: i64) -> GqlResult<User> {
            let pool = ctx.data::<PgPool>()?;
            let config = ctx.data::<BackpressureConfig>()?;

            // Acquire connection with backpressure
            let mut conn = acquire_with_backpressure(pool, "graphql-gateway", *config)
                .await
                .map_err(|e| {
                    // GraphQL error with structured extension
                    tracing::warn!(user_id = %id, error = %e, "Pool exhausted");
                    async_graphql::Error::new("Service temporarily overloaded")
                        .extend_with(|_, ext| {
                            ext.set("code", "UNAVAILABLE");
                            ext.set("retry_after_seconds", 5);
                            ext.set("utilization", e.utilization);
                        })
                })?;

            let user = sqlx::query_as::<_, User>("SELECT * FROM users WHERE id = $1")
                .bind(id)
                .fetch_one(&mut *conn)
                .await?;

            Ok(user)
        }

        /// Example: Get multiple users with backpressure
        async fn users(
            &self,
            ctx: &Context<'_>,
            ids: Vec<i64>,
        ) -> GqlResult<Vec<User>> {
            let pool = ctx.data::<PgPool>()?;
            let config = ctx.data::<BackpressureConfig>()?;

            let mut conn = acquire_with_backpressure(pool, "graphql-gateway", *config)
                .await
                .map_err(|e| {
                    async_graphql::Error::new("Service overloaded")
                        .extend_with(|_, ext| ext.set("code", "UNAVAILABLE"))
                })?;

            let users =
                sqlx::query_as::<_, User>("SELECT * FROM users WHERE id = ANY($1)")
                    .bind(&ids)
                    .fetch_all(&mut *conn)
                    .await?;

            Ok(users)
        }
    }

    pub struct MutationRoot;

    #[Object]
    impl MutationRoot {
        /// Example GraphQL mutation with backpressure
        async fn create_user(
            &self,
            ctx: &Context<'_>,
            username: String,
            email: String,
        ) -> GqlResult<User> {
            let pool = ctx.data::<PgPool>()?;
            let config = ctx.data::<BackpressureConfig>()?;

            let mut conn = acquire_with_backpressure(pool, "graphql-gateway", *config)
                .await
                .map_err(|e| async_graphql::Error::new(e.to_string()))?;

            let user = sqlx::query_as::<_, User>(
                "INSERT INTO users (username, email) VALUES ($1, $2) RETURNING *",
            )
            .bind(&username)
            .bind(&email)
            .fetch_one(&mut *conn)
            .await?;

            Ok(user)
        }
    }

    /// Build GraphQL schema with backpressure config
    pub fn build_schema(pool: PgPool) -> Schema<QueryRoot, MutationRoot, async_graphql::EmptySubscription> {
        let config = BackpressureConfig::from_env();

        Schema::build(QueryRoot, MutationRoot, async_graphql::EmptySubscription)
            .data(pool)
            .data(config) // Add backpressure config to context
            .finish()
    }

    // Stub types
    #[derive(Debug)]
    pub struct User {
        pub id: i64,
        pub username: String,
        pub email: String,
    }
}

//==============================================================================
// Example 4: messaging-service (Middleware Integration)
//==============================================================================

mod messaging_service_example {
    use axum::{
        extract::{Request, State},
        http::StatusCode,
        middleware::{self, Next},
        response::Response,
        Router,
    };
    use db_pool::{BackpressureConfig, PoolExhaustedError};
    use sqlx::PgPool;
    use std::sync::Arc;

    /// Middleware that checks pool health BEFORE processing request
    ///
    /// This is more efficient than checking in each handler
    pub async fn check_pool_health(
        State(pool): State<Arc<PgPool>>,
        State(config): State<Arc<BackpressureConfig>>,
        request: Request,
        next: Next,
    ) -> Result<Response, (StatusCode, String)> {
        // Pre-check pool utilization
        let size = pool.size() as f64;
        let idle = pool.num_idle() as f64;
        let active = size - idle;
        let max = pool.options().get_max_connections() as f64;

        let utilization = if max > 0.0 { active / max } else { 0.0 };

        if utilization > config.threshold {
            tracing::warn!(
                utilization = %utilization,
                threshold = %config.threshold,
                "Pool exhausted - rejecting request in middleware"
            );
            return Err((
                StatusCode::SERVICE_UNAVAILABLE,
                "Service temporarily overloaded".to_string(),
            ));
        }

        // Pool healthy - continue to handler
        Ok(next.run(request).await)
    }

    /// Build router with middleware-based backpressure
    pub fn build_router_with_middleware(pool: PgPool) -> Router {
        let config = BackpressureConfig::from_env();

        Router::new()
            .route("/messages", axum::routing::post(send_message_handler))
            .route("/messages/:id", axum::routing::get(get_message_handler))
            // Apply backpressure middleware to all routes
            .layer(middleware::from_fn_with_state(
                Arc::new(pool.clone()),
                check_pool_health,
            ))
            .layer(middleware::from_fn_with_state(
                Arc::new(config),
                check_pool_health,
            ))
            .with_state(Arc::new(pool))
    }

    // Stub handlers
    async fn send_message_handler(State(_pool): State<Arc<PgPool>>) -> StatusCode {
        StatusCode::OK
    }

    async fn get_message_handler(State(_pool): State<Arc<PgPool>>) -> StatusCode {
        StatusCode::OK
    }
}

//==============================================================================
// Main function showing initialization for all services
//==============================================================================

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize tracing
    tracing_subscriber::fmt::init();

    // Example 1: user-service (gRPC)
    let user_pool = db_pool::create_pool(db_pool::DbConfig::for_service("user-service")).await?;
    let user_service = user_service_example::UserServiceImpl::new(user_pool);
    println!("✅ user-service initialized with backpressure");

    // Example 2: feed-service (REST)
    let feed_pool = db_pool::create_pool(db_pool::DbConfig::for_service("feed-service")).await?;
    let feed_state = Arc::new(feed_service_example::AppState::new(feed_pool));
    let feed_router = feed_service_example::build_router(feed_state);
    println!("✅ feed-service initialized with backpressure");

    // Example 3: graphql-gateway (GraphQL)
    let graphql_pool =
        db_pool::create_pool(db_pool::DbConfig::for_service("graphql-gateway")).await?;
    let graphql_schema = graphql_gateway_example::build_schema(graphql_pool);
    println!("✅ graphql-gateway initialized with backpressure");

    // Example 4: messaging-service (Middleware)
    let messaging_pool =
        db_pool::create_pool(db_pool::DbConfig::for_service("messaging-service")).await?;
    let messaging_router = messaging_service_example::build_router_with_middleware(messaging_pool);
    println!("✅ messaging-service initialized with backpressure middleware");

    println!("\n✅ All services initialized successfully!");
    println!("📊 Monitoring metrics available at /metrics endpoint");
    println!("🔧 Configure threshold via DB_POOL_BACKPRESSURE_THRESHOLD env var");

    Ok(())
}
