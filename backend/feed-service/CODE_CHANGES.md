# Code Changes Summary - feed-service Refactoring

## Files Modified

### 1. grpc-clients Library (Shared Infrastructure)

#### `/backend/libs/grpc-clients/proto/ranking.proto` ✅ NEW
- **Action**: Copied from ranking-service
- **Purpose**: Client-side proto definition for ranking API

#### `/backend/libs/grpc-clients/build.rs`
```rust
+ // Compile ranking-service proto (from local proto directory)
+ tonic_build::configure()
+     .build_server(false)
+     .build_client(true)
+     .compile_protos(&["proto/ranking.proto"], &["proto"])
+     .unwrap_or_else(|e| panic!("Failed to compile ranking_service: {}", e));
```

#### `/backend/libs/grpc-clients/src/config.rs`
```rust
+ /// Ranking Service endpoint
+ pub ranking_service_url: String,

// In from_env():
+ ranking_service_url: env::var("GRPC_RANKING_SERVICE_URL")
+     .unwrap_or_else(|_| "http://ranking-service:9088".to_string()),

// In development():
+ ranking_service_url: "http://localhost:9088".to_string(),
```

#### `/backend/libs/grpc-clients/src/lib.rs`
```rust
+ pub mod ranking_service {
+     pub mod v1 {
+         tonic::include_proto!("ranking.v1");
+     }
+     pub use v1::*;
+ }

+ pub use nova::ranking_service::ranking_service_client::RankingServiceClient;

  #[derive(Clone)]
  pub struct GrpcClientPool {
      // ...existing clients...
+     ranking_client: Arc<RankingServiceClient<Channel>>,
  }

  impl GrpcClientPool {
      pub async fn new(config: &config::GrpcConfig) -> Result<Self, Box<dyn std::error::Error>> {
          // ...existing initialization...
+         let ranking_client = Arc::new(RankingServiceClient::new(
+             connect_or_placeholder(config, &config.ranking_service_url, "ranking-service").await,
+         ));

          Ok(Self {
              // ...existing clients...
+             ranking_client,
          })
      }

+     pub fn ranking(&self) -> RankingServiceClient<Channel> {
+         (*self.ranking_client).clone()
+     }
  }
```

---

### 2. feed-service Updates

#### `/backend/feed-service/Cargo.toml`
```toml
- # Recommendation-specific
- ndarray = "0.15"
- tract-onnx = "0.21"
- once_cell = "1.19"

+ # Kafka for event streaming
  rdkafka.workspace = true
```

#### `/backend/feed-service/src/config/mod.rs`
```rust
  #[derive(Debug, Clone, Serialize, Deserialize)]
  pub struct GrpcConfig {
      pub user_service_url: String,
+     pub ranking_service_url: String,
      #[serde(default = "default_grpc_timeout_secs")]
      pub timeout_secs: u64,
  }

  impl Config {
      pub fn from_env() -> Result<Self, Box<dyn std::error::Error>> {
          Ok(Config {
              // ...existing config...
              grpc: GrpcConfig {
                  user_service_url: std::env::var("USER_SERVICE_GRPC_URL")
                      .unwrap_or_else(|_| "http://127.0.0.1:50051".to_string()),
+                 ranking_service_url: std::env::var("RANKING_SERVICE_GRPC_URL")
+                     .unwrap_or_else(|_| "http://127.0.0.1:9088".to_string()),
                  // ...
              },
          })
      }
  }
```

#### `/backend/feed-service/src/handlers/recommendation.rs`
```rust
- use crate::services::RecommendationServiceV2;
+ use grpc_clients::RankingServiceClient;
+ use grpc_clients::nova::ranking_service::v1::{RankFeedRequest, RecallConfig};
+ use tracing::{debug, error, warn};

  pub struct RecommendationHandlerState {
-     pub service: Arc<RecommendationServiceV2>,
+     pub ranking_client: Arc<RankingServiceClient<tonic::transport::Channel>>,
+     pub db_pool: sqlx::PgPool,
  }

  #[get("/api/v1/recommendations")]
  pub async fn get_recommendations(
      req: HttpRequest,
      query: web::Query<RecommendationQuery>,
      state: web::Data<RecommendationHandlerState>,
  ) -> Result<HttpResponse> {
      // Extract user ID...
      let limit = query.limit.min(100).max(1);

-     match state.service.get_recommendations(user_id, limit).await {
-         Ok(posts) => {
-             let count = posts.len();
-             Ok(HttpResponse::Ok().json(RecommendationResponse { posts, count }))
-         }
-         Err(err) => {
-             error!("Failed to get recommendations: {:?}", err);
-             Err(err)
-         }
-     }

+     // Call ranking-service via gRPC
+     let ranking_request = RankFeedRequest {
+         user_id: user_id.to_string(),
+         limit: limit as i32,
+         recall_config: Some(RecallConfig {
+             graph_recall_limit: 200,
+             trending_recall_limit: 100,
+             personalized_recall_limit: 100,
+             enable_diversity: true,
+         }),
+     };
+
+     let mut ranking_client = (*state.ranking_client).clone();
+
+     match ranking_client.rank_feed(ranking_request).await {
+         Ok(response) => {
+             let ranked_posts = response.into_inner();
+             let posts: Vec<Uuid> = ranked_posts
+                 .posts
+                 .into_iter()
+                 .filter_map(|p| Uuid::parse_str(&p.post_id).ok())
+                 .collect();
+
+             let count = posts.len();
+             Ok(HttpResponse::Ok().json(RecommendationResponse { posts, count }))
+         }
+         Err(err) => {
+             warn!("Ranking service unavailable: {:?}, falling back to chronological feed", err);
+
+             // Fallback: Simple chronological ordering
+             match fetch_chronological_feed(&state.db_pool, user_id, limit).await {
+                 Ok(posts) => {
+                     let count = posts.len();
+                     Ok(HttpResponse::Ok().json(RecommendationResponse { posts, count }))
+                 }
+                 Err(fallback_err) => {
+                     error!("Fallback feed fetch failed: {:?}", fallback_err);
+                     Err(AppError::Internal(format!("Failed to fetch feed: {:?}", fallback_err)))
+                 }
+             }
+         }
+     }
  }

+ /// Fallback: Fetch chronological feed when ranking service is down
+ async fn fetch_chronological_feed(
+     db_pool: &sqlx::PgPool,
+     user_id: Uuid,
+     limit: usize,
+ ) -> Result<Vec<Uuid>> {
+     let limit = limit as i64;
+
+     // Get posts from followed users, ordered by recency
+     let rows = sqlx::query(
+         "SELECT DISTINCT p.id
+          FROM posts p
+          JOIN follows f ON f.followee_id = p.user_id
+          WHERE f.follower_id = $1
+            AND p.status = 'published'
+            AND p.soft_delete IS NULL
+          ORDER BY p.created_at DESC
+          LIMIT $2",
+     )
+     .bind(user_id)
+     .bind(limit)
+     .fetch_all(db_pool)
+     .await
+     .map_err(|e| AppError::Internal(format!("Database error: {}", e)))?;
+
+     let posts: Vec<Uuid> = rows
+         .into_iter()
+         .filter_map(|row| row.try_get::<Uuid, _>("id").ok())
+         .collect();
+
+     Ok(posts)
+ }

  #[get("/api/v1/recommendations/model-info")]
- pub async fn get_model_info(state: web::Data<RecommendationHandlerState>) -> Result<HttpResponse> {
-     let info = state.service.get_model_info().await;
-     Ok(HttpResponse::Ok().json(ModelInfoResponse {
-         collaborative_version: info.collaborative_version,
-         content_version: info.content_version,
-         onnx_version: info.onnx_version,
-         deployed_at: info.deployed_at.to_rfc3339(),
-     }))
- }
+ pub async fn get_model_info(_state: web::Data<RecommendationHandlerState>) -> Result<HttpResponse> {
+     Ok(HttpResponse::Ok().json(ModelInfoResponse {
+         collaborative_version: "delegated-to-ranking-service".to_string(),
+         content_version: "delegated-to-ranking-service".to_string(),
+         onnx_version: "delegated-to-ranking-service".to_string(),
+         deployed_at: chrono::Utc::now().to_rfc3339(),
+     }))
+ }

  #[post("/api/v1/recommendations/rank")]
  pub async fn rank_candidates(
      req: HttpRequest,
-     body: web::Json<RankingRequest>,
-     state: web::Data<RecommendationHandlerState>,
+     _body: web::Json<RankingRequest>,
+     _state: web::Data<RecommendationHandlerState>,
  ) -> Result<HttpResponse> {
-     // ...ranking logic...
-     match state.service.rank_with_context(...).await {
-         Ok(posts) => { ... }
-         Err(err) => { ... }
-     }
+     Err(AppError::BadRequest(
+         "This endpoint is deprecated. Use ranking-service directly.".to_string(),
+     ))
  }

  #[post("/api/v1/recommendations/semantic-search")]
  pub async fn semantic_search(
      req: HttpRequest,
-     body: web::Json<SemanticSearchRequest>,
-     state: web::Data<RecommendationHandlerState>,
+     _body: web::Json<SemanticSearchRequest>,
+     _state: web::Data<RecommendationHandlerState>,
  ) -> Result<HttpResponse> {
-     // ...semantic search logic...
-     match state.service.search_semantically_similar(...).await {
-         Ok(results) => { ... }
-         Err(err) => { ... }
-     }
+     Err(AppError::BadRequest(
+         "This endpoint is deprecated. Use feature-store or ranking-service directly.".to_string(),
+     ))
  }
```

#### `/backend/feed-service/src/main.rs`
```rust
- use recommendation_service::services::{RecommendationEventConsumer, RecommendationServiceV2};
- use rdkafka::config::ClientConfig;
- use rdkafka::consumer::{Consumer, StreamConsumer};
- use rdkafka::Message;
- use serde_json::from_slice;
- use tracing::{error, info, warn};

+ use tracing::{error, info};

- /// Start Kafka consumer for recommendation events
- async fn start_kafka_consumer(
-     service: Arc<RecommendationServiceV2>,
-     config: &Config,
- ) -> Result<(), Box<dyn std::error::Error>> {
-     // ...Kafka consumer implementation...
- }
+ // Kafka consumer removed - recommendation events now handled by ranking-service

  #[actix_web::main]
  async fn main() -> io::Result<()> {
      // ...initialization...

-     // Initialize recommendation service
-     let rec_config = recommendation_service::services::RecommendationConfig {
-         collaborative_model_path: config.recommendation.collaborative_model_path.clone(),
-         content_model_path: config.recommendation.content_model_path.clone(),
-         onnx_model_path: config.recommendation.onnx_model_path.clone(),
-         hybrid_weights: recommendation_service::services::HybridWeights::balanced(),
-         enable_ab_testing: config.recommendation.enable_ab_testing,
-     };
-
-     let recommendation_svc = match RecommendationServiceV2::new(
-         rec_config,
-         db_pool.get_ref().clone(),
-         auth_client.clone(),
-     ).await {
-         Ok(service) => {
-             tracing::info!("Recommendation service initialized successfully");
-             Arc::new(service)
-         }
-         Err(e) => {
-             tracing::error!("Failed to initialize recommendation service: {:?}", e);
-             return Err(io::Error::new(
-                 io::ErrorKind::Other,
-                 format!("Failed to initialize recommendation service: {:?}", e),
-             ));
-         }
-     };
-
-     let rec_handler_state = web::Data::new(RecommendationHandlerState {
-         service: Arc::clone(&recommendation_svc),
-     });
-
-     // Start Kafka consumer in background task
-     let kafka_svc = Arc::clone(&recommendation_svc);
-     let kafka_config = config.clone();
-     tokio::spawn(async move {
-         if let Err(e) = start_kafka_consumer(kafka_svc, &kafka_config).await {
-             error!("Kafka consumer failed: {:?}", e);
-         }
-     });
-     info!("Kafka consumer task spawned");

+     // Initialize RankingServiceClient from gRPC pool
+     let ranking_client = Arc::new(grpc_pool.ranking());
+     tracing::info!("RankingService gRPC client initialized from pool");
+
+     let rec_handler_state = web::Data::new(RecommendationHandlerState {
+         ranking_client,
+         db_pool: db_pool.get_ref().clone(),
+     });
+
+     // Kafka consumer removed - recommendation events now handled by ranking-service
+     info!("Feed-service simplified - ranking delegated to ranking-service");

      // ...rest of main...
  }
```

#### `/backend/feed-service/src/services/mod.rs`
```rust
- //! Service layer for recommendation engine
- //!
- //! Implements hybrid recommendation algorithm combining:
- //! - Collaborative filtering (user-user, item-item)
- //! - Content-based filtering (TF-IDF features)
- //! - A/B testing framework for experiment tracking
- //! - ONNX model serving for deep learning inference

+ //! Service layer for feed-service
+ //!
+ //! Phase D Refactoring:
+ //! ✅ ML ranking logic moved to ranking-service
+ //! ✅ Feed-service now focuses on feed assembly and caching
+ //! ⚠️  Legacy recommendation_v2 module kept for backward compatibility (to be removed in Phase E)
+ //!
+ //! Active modules:
+ //! - trending: Trending content computation
+ //! - (recommendation_v2, kafka_consumer, vector_search: deprecated, use ranking-service)

- pub mod kafka_consumer;
- pub mod recommendation_v2;
  pub mod trending;
- pub mod vector_search;

- pub use kafka_consumer::{
-     ExperimentVariant, RecommendationEventBatch, RecommendationEventConsumer,
-     RecommendationEventType, RecommendationKafkaEvent,
- };
- pub use recommendation_v2::{
-     ABTestingFramework, CollaborativeFilteringModel, ContentBasedModel, Experiment,
-     ExperimentEvent, HybridRanker, HybridWeights, ModelInfo, ONNXModelServer, RankedPost,
-     RankingStrategy, RecommendationConfig, RecommendationServiceV2, UserContext, Variant,
- };

+ // Legacy modules (deprecated - use ranking-service instead)
+ #[allow(dead_code)]
+ pub mod kafka_consumer;
+ #[allow(dead_code)]
+ pub mod recommendation_v2;
+ #[allow(dead_code)]
+ pub mod vector_search;

  pub use trending::TrendingService;
- pub use vector_search::{PostEmbedding, VectorSearchResult, VectorSearchService};
```

#### `/backend/feed-service/src/lib.rs`
```rust
- // Re-export recommendation service components
- pub use services::{
-     ABTestingFramework, CollaborativeFilteringModel, ContentBasedModel, HybridRanker,
-     HybridWeights, ModelInfo, ONNXModelServer, RankedPost, RankingStrategy, RecommendationConfig,
-     RecommendationServiceV2, UserContext, Variant,
- };

+ // Re-export trending service components (ML recommendation moved to ranking-service)
+ // Keeping only services needed for feed assembly and caching
```

---

## Summary Statistics

### Lines Added: ~180
### Lines Removed: ~220
### Net Change: -40 lines (simpler!)

### Dependencies Removed:
- `ndarray` (0.15)
- `tract-onnx` (0.21)
- `once_cell` (1.19)

### Dependencies Added:
- `grpc-clients::RankingServiceClient` (via existing dependency)

### Compilation Units Deprecated:
- `src/services/recommendation_v2/` (kept for backward compat)
- `src/services/kafka_consumer.rs` (kept for backward compat)
- `src/services/vector_search.rs` (kept for backward compat)

---

## Testing Commands

### Build grpc-clients:
```bash
cd backend/libs/grpc-clients
cargo build
```

### Build feed-service:
```bash
cd backend/feed-service
cargo build
```

### Run tests:
```bash
cargo test --all
```

### Check for unused dependencies:
```bash
cargo machete backend/feed-service
```

---

## Next Steps

1. **Test Compilation**: Ensure all services compile cleanly
2. **Integration Tests**: Add ranking-service mock tests
3. **Load Testing**: Verify performance under load
4. **Deployment**: Roll out to staging environment
5. **Monitor**: Track fallback activations and latency
6. **Phase E**: Remove deprecated ML code after validation

