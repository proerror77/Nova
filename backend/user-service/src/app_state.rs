//! Central application state management
//!
//! This module defines the single source of truth for all application dependencies.
//! Follows the principle: "Clear data ownership is better than scattered references"

use crate::config::Config;
use crate::db::ch_client::ClickHouseClient;
use crate::cache::FeedCache;
use crate::middleware::RateLimiter;
use crate::services::{
    feed_ranking::FeedRankingService,
    streaming::{
        StreamRepository, StreamService, StreamDiscoveryService, StreamAnalyticsService,
        ViewerCounter, StreamChatStore, RtmpWebhookHandler, StreamChatHandlerState,
    },
    graph::GraphService,
    video_service::VideoService,
    deep_learning_inference::DeepLearningInferenceService,
    kafka_producer::EventProducer,
    oauth::jwks_cache::JWKSCache,
    recommendation_v2::RecommendationServiceV2,
};
use redis::aio::ConnectionManager;
use sqlx::PgPool;
use std::sync::Arc;
use tokio::sync::Mutex;
use actix_web::web;

/// Central application state - single source of truth
/// 
/// Contains all major components needed by handlers.
/// No scattered Arc/Mutex references - everything goes through AppState.
#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
    pub redis: ConnectionManager,
    pub clickhouse: Arc<ClickHouseClient>,
    pub config: Arc<Config>,
    pub event_producer: Arc<EventProducer>,
    pub services: Arc<AppServices>,
    pub rate_limiter: Arc<RateLimiter>,
}

/// Grouped services for better organization
/// 
/// Separates concerns:
/// - feed_* = Feed ranking and recommendations
/// - stream_* = Live streaming services
/// - graph = Relationship graph (Neo4j)
/// - video = Video processing
pub struct AppServices {
    // Feed services
    pub feed_ranking: Arc<FeedRankingService>,
    pub rec_v2: Option<Arc<RecommendationServiceV2>>,
    
    // Streaming services
    pub stream_service: Arc<Mutex<StreamService>>,
    pub stream_discovery: Arc<Mutex<StreamDiscoveryService>>,
    pub stream_analytics: Arc<StreamAnalyticsService>,
    pub stream_rtmp_handler: Arc<Mutex<RtmpWebhookHandler>>,
    pub stream_chat_state: web::Data<StreamChatHandlerState>,
    
    // Graph service (optional)
    pub graph_service: GraphService,
    
    // Video services
    pub video_service: Arc<VideoService>,
    pub deep_learning_service: Arc<DeepLearningInferenceService>,
    
    // JWT keys
    pub jwks_cache: Arc<JWKSCache>,
}

impl AppState {
    /// Initialize all application state
    /// 
    /// This is the only place where dependencies are wired.
    /// Clean separation of concerns - each init_* method handles one aspect.
    pub async fn initialize(config: Config) -> Result<Self, Box<dyn std::error::Error>> {
        tracing::info!("Initializing application state...");
        
        // 1. Core infrastructure
        let db = Self::init_database(&config).await?;
        let redis = Self::init_redis(&config).await?;
        let clickhouse = Self::init_clickhouse(&config).await?;
        
        // 2. Messaging
        let event_producer = Self::init_kafka(&config).await?;
        
        // 3. Rate limiting
        let rate_limiter = Self::init_rate_limiter(&redis, &config).await?;
        
        // 4. Services
        let services = AppServices::initialize(
            &db,
            &redis,
            &clickhouse,
            &event_producer,
            &config,
        ).await?;
        
        Ok(Self {
            db,
            redis,
            clickhouse,
            config: Arc::new(config),
            event_producer,
            services: Arc::new(services),
            rate_limiter,
        })
    }
    
    async fn init_database(config: &Config) -> Result<PgPool, Box<dyn std::error::Error>> {
        tracing::info!("Initializing database pool...");
        let pool = crate::db::create_pool(
            &config.database.url,
            config.database.max_connections,
        ).await?;
        
        if !config.is_production() {
            tracing::info!("Running database migrations...");
            match crate::db::run_migrations(&pool).await {
                Ok(_) => tracing::info!("Migrations completed"),
                Err(e) => {
                    // Tolerate migration errors in dev (may have version mismatches)
                    tracing::warn!("Migration error (tolerated in non-prod): {:#}", e);
                }
            }
        }
        
        Ok(pool)
    }
    
    async fn init_redis(config: &Config) -> Result<ConnectionManager, Box<dyn std::error::Error>> {
        tracing::info!("Initializing Redis connection...");
        let client = redis::Client::open(config.redis.url.as_str())?;
        let manager = client.get_connection_manager().await?;
        tracing::info!("Redis connection established");
        Ok(manager)
    }
    
    async fn init_clickhouse(config: &Config) -> Result<Arc<ClickHouseClient>, Box<dyn std::error::Error>> {
        tracing::info!("Initializing ClickHouse client...");
        let client = Arc::new(ClickHouseClient::new(
            &config.clickhouse.url,
            &config.clickhouse.database,
            &config.clickhouse.username,
            &config.clickhouse.password,
            config.clickhouse.timeout_ms,
        ));
        
        if let Err(e) = client.health_check().await {
            tracing::warn!("ClickHouse health check failed: {}", e);
        } else {
            tracing::info!("ClickHouse connection validated");
        }
        
        Ok(client)
    }
    
    async fn init_kafka(config: &Config) -> Result<Arc<EventProducer>, Box<dyn std::error::Error>> {
        tracing::info!("Initializing Kafka producer...");
        let producer = Arc::new(
            EventProducer::new(&config.kafka.brokers, config.kafka.events_topic.clone())?
        );
        Ok(producer)
    }
    
    async fn init_rate_limiter(
        redis: &ConnectionManager,
        config: &Config,
    ) -> Result<Arc<RateLimiter>, Box<dyn std::error::Error>> {
        use crate::middleware::rate_limit::RateLimitConfig;
        
        let rate_limit_config = RateLimitConfig {
            max_requests: 100,
            window_seconds: 900,
        };
        
        let rate_limiter = RateLimiter::new(redis.clone(), rate_limit_config);
        tracing::info!("Rate limiter initialized: 100 requests per 15 minutes");
        Ok(Arc::new(rate_limiter))
    }
}

impl AppServices {
    /// Initialize all service components
    async fn initialize(
        db: &PgPool,
        redis: &ConnectionManager,
        clickhouse: &Arc<ClickHouseClient>,
        event_producer: &Arc<EventProducer>,
        config: &Config,
    ) -> Result<Self, Box<dyn std::error::Error>> {
        tracing::info!("Initializing services...");
        
        // Feed services
        let feed_cache = Arc::new(Mutex::new(FeedCache::new(redis.clone(), 120)));
        let feed_ranking = Arc::new(FeedRankingService::new(
            clickhouse.clone(),
            feed_cache.clone(),
        ));
        tracing::info!("Feed ranking service initialized");
        
        // Optional: Recommendation V2
        let rec_v2 = if std::env::var("RECOMMENDATION_V2_INIT").unwrap_or_default() == "true" {
            match RecommendationServiceV2::new(
                crate::config::video_config::VideoConfig::from_env().into(),
                db.clone(),
            ).await {
                Ok(svc) => {
                    tracing::info!("Recommendation V2 service initialized");
                    Some(Arc::new(svc))
                }
                Err(e) => {
                    tracing::warn!("Failed to initialize Recommendation V2: {}", e);
                    None
                }
            }
        } else {
            None
        };
        
        // Streaming services
        let stream_repo = StreamRepository::new(db.clone());
        let stream_viewer_counter = ViewerCounter::new(redis.clone());
        let stream_chat_store = StreamChatStore::new(redis.clone(), 200);
        
        let rtmp_base_url = std::env::var("STREAMING_RTMP_BASE_URL")
            .unwrap_or_else(|_| "rtmp://localhost/live".to_string());
        let hls_cdn_url = std::env::var("STREAMING_HLS_BASE_URL")
            .unwrap_or_else(|_| "https://cdn.nova.local".to_string());
        
        let stream_service = Arc::new(Mutex::new(StreamService::new(
            stream_repo.clone(),
            stream_viewer_counter.clone(),
            stream_chat_store.clone(),
            event_producer.clone(),
            rtmp_base_url.clone(),
            hls_cdn_url.clone(),
        )));
        
        let stream_discovery = Arc::new(Mutex::new(StreamDiscoveryService::new(
            stream_repo.clone(),
            stream_viewer_counter.clone(),
        )));
        
        let stream_analytics = Arc::new(StreamAnalyticsService::new(stream_repo.clone()));
        
        let stream_rtmp_handler = Arc::new(Mutex::new(RtmpWebhookHandler::new(
            stream_repo,
            ViewerCounter::new(redis.clone()),
            hls_cdn_url,
        )));
        
        let stream_chat_state = web::Data::new(StreamChatHandlerState::new(
            StreamChatStore::new(redis.clone(), 200),
            event_producer.clone(),
            db.clone(),
        ));
        
        tracing::info!("Streaming services initialized");
        
        // Graph service (optional)
        let graph_service = match GraphService::new(&config.graph).await {
            Ok(svc) => {
                if svc.is_enabled() {
                    tracing::info!("Neo4j graph service enabled");
                } else {
                    tracing::info!("Neo4j graph service disabled");
                }
                svc
            }
            Err(e) => {
                tracing::warn!("Neo4j service init failed: {} (graph disabled)", e);
                GraphService::new(&crate::config::GraphConfig {
                    enabled: false,
                    neo4j_uri: String::new(),
                    neo4j_user: String::new(),
                    neo4j_password: String::new(),
                }).await?
            }
        };
        
        // Video services
        let video_service = Arc::new(VideoService::new(
            crate::config::video_config::VideoConfig::from_env(),
        ));
        
        let deep_learning_service = Arc::new(DeepLearningInferenceService::new(
            crate::config::video_config::VideoConfig::from_env().inference,
        ));
        
        // JWT cache
        let redis_client = redis::Client::open(config.redis.url.as_str())?;
        let jwks_cache = Arc::new(JWKSCache::new(redis_client));
        
        tracing::info!("All services initialized successfully");
        
        Ok(Self {
            feed_ranking,
            rec_v2,
            stream_service,
            stream_discovery,
            stream_analytics,
            stream_rtmp_handler,
            stream_chat_state,
            graph_service,
            video_service,
            deep_learning_service,
            jwks_cache,
        })
    }
}
