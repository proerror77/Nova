//! Background task management
//!
//! Centralizes spawning and management of all long-running background tasks
//! (CDC consumer, events consumer, jobs, stories cleanup, etc.)

use crate::app_state::AppState;
use crate::config::video_config;
use crate::services::{
    cdc::{CdcConsumer, CdcConsumerConfig},
    events::{EventsConsumer, EventsConsumerConfig, EventDeduplicator},
    deep_learning_inference::DeepLearningInferenceService,
    stories::StoriesService,
    job_queue, video_job_queue,
};
use std::sync::Arc;
use tokio::sync::broadcast;

/// Background task handles for graceful shutdown
pub struct BackgroundTasks {
    pub cdc_handle: Option<tokio::task::JoinHandle<()>>,
    pub events_handle: tokio::task::JoinHandle<()>,
    pub jobs_handle: tokio::task::JoinHandle<()>,
    pub stories_cleanup_handle: tokio::task::JoinHandle<()>,
    pub milvus_health_check_handle: Option<tokio::task::JoinHandle<()>>,
}

/// Spawn all background tasks
pub async fn spawn_background_tasks(state: AppState) -> Result<BackgroundTasks, Box<dyn std::error::Error>> {
    tracing::info!("Spawning background tasks...");
    
    // CDC consumer (optional)
    let cdc_handle = if std::env::var("ENABLE_CDC").unwrap_or_default() == "true" {
        Some(spawn_cdc_consumer(&state).await?)
    } else {
        tracing::info!("CDC consumer disabled (ENABLE_CDC=false)");
        None
    };
    
    // Events consumer
    let events_handle = spawn_events_consumer(&state).await?;
    
    // Background jobs (suggested users, trending, cache warmup)
    let jobs_handle = spawn_background_jobs(&state).await?;
    
    // Stories cleanup worker
    let stories_cleanup_handle = spawn_stories_cleanup(&state).await?;
    
    // Milvus health check (optional)
    let milvus_health_check_handle = if std::env::var("MILVUS_ENABLED").unwrap_or_default() == "true" {
        Some(spawn_milvus_health_check())
    } else {
        None
    };
    
    tracing::info!("All background tasks spawned successfully");
    
    Ok(BackgroundTasks {
        cdc_handle,
        events_handle,
        jobs_handle,
        stories_cleanup_handle,
        milvus_health_check_handle,
    })
}

/// Gracefully shutdown all background tasks
pub async fn shutdown_background_tasks(tasks: BackgroundTasks) {
    tracing::info!("Shutting down background tasks...");
    
    // CDC consumer
    if let Some(cdc_handle) = tasks.cdc_handle {
        cdc_handle.abort();
        match tokio::time::timeout(std::time::Duration::from_secs(5), cdc_handle).await {
            Ok(Ok(())) => tracing::info!("CDC consumer shut down gracefully"),
            Ok(Err(_)) => tracing::info!("CDC consumer aborted"),
            Err(_) => tracing::warn!("CDC consumer did not shut down within timeout"),
        }
    }
    
    // Events consumer
    tasks.events_handle.abort();
    match tokio::time::timeout(std::time::Duration::from_secs(5), tasks.events_handle).await {
        Ok(Ok(())) => tracing::info!("Events consumer shut down gracefully"),
        Ok(Err(_)) => tracing::info!("Events consumer aborted"),
        Err(_) => tracing::warn!("Events consumer did not shut down within timeout"),
    }
    
    // Jobs
    tasks.jobs_handle.abort();
    match tokio::time::timeout(std::time::Duration::from_secs(5), tasks.jobs_handle).await {
        Ok(Ok(())) => tracing::info!("Background jobs shut down gracefully"),
        Ok(Err(_)) => tracing::info!("Background jobs aborted"),
        Err(_) => tracing::warn!("Background jobs did not shut down within timeout"),
    }
    
    // Stories cleanup
    tasks.stories_cleanup_handle.abort();
    match tokio::time::timeout(std::time::Duration::from_secs(5), tasks.stories_cleanup_handle).await {
        Ok(Ok(())) => tracing::info!("Stories cleanup shut down gracefully"),
        Ok(Err(_)) => tracing::info!("Stories cleanup aborted"),
        Err(_) => tracing::warn!("Stories cleanup did not shut down within timeout"),
    }
    
    // Milvus health check
    if let Some(milvus_handle) = tasks.milvus_health_check_handle {
        milvus_handle.abort();
        match tokio::time::timeout(std::time::Duration::from_secs(5), milvus_handle).await {
            Ok(Ok(())) => tracing::info!("Milvus health check shut down gracefully"),
            Ok(Err(_)) => tracing::info!("Milvus health check aborted"),
            Err(_) => tracing::warn!("Milvus health check did not shut down within timeout"),
        }
    }
    
    tracing::info!("All background tasks shut down complete");
}

/// Spawn CDC consumer (PostgreSQL → Kafka → ClickHouse)
async fn spawn_cdc_consumer(state: &AppState) -> Result<tokio::task::JoinHandle<()>, Box<dyn std::error::Error>> {
    let cdc_config = CdcConsumerConfig {
        brokers: state.config.kafka.brokers.clone(),
        group_id: "nova-cdc-consumer-v1".to_string(),
        topics: vec![
            "cdc.posts".to_string(),
            "cdc.follows".to_string(),
            "cdc.comments".to_string(),
            "cdc.likes".to_string(),
        ],
        max_concurrent_inserts: 10,
    };
    
    let ch_writable = Arc::new(
        crate::db::ch_client::ClickHouseClient::new_writable(
            &state.config.clickhouse.url,
            &state.config.clickhouse.database,
            &state.config.clickhouse.username,
            &state.config.clickhouse.password,
            state.config.clickhouse.timeout_ms,
        )
    );
    
    let cdc_consumer = CdcConsumer::new(
        cdc_config,
        ch_writable.as_ref().clone(),
        state.db.clone(),
    ).await?;
    
    let handle = tokio::spawn(async move {
        if let Err(e) = cdc_consumer.run().await {
            tracing::error!("CDC consumer error: {}", e);
        }
    });
    
    tracing::info!("CDC consumer spawned");
    Ok(handle)
}

/// Spawn events consumer (Kafka → ClickHouse for analytics)
async fn spawn_events_consumer(state: &AppState) -> Result<tokio::task::JoinHandle<()>, Box<dyn std::error::Error>> {
    let ch_writable = Arc::new(
        crate::db::ch_client::ClickHouseClient::new_writable(
            &state.config.clickhouse.url,
            &state.config.clickhouse.database,
            &state.config.clickhouse.username,
            &state.config.clickhouse.password,
            state.config.clickhouse.timeout_ms,
        )
    );
    
    let events_config = EventsConsumerConfig {
        brokers: state.config.kafka.brokers.clone(),
        group_id: "nova-events-consumer-v1".to_string(),
        topic: state.config.kafka.events_topic.clone(),
        batch_size: 100,
        max_concurrent_inserts: 5,
    };
    
    let redis_client = redis::Client::open(state.config.redis.url.as_str())?;
    let event_deduplicator = EventDeduplicator::new(redis_client, 3600);
    
    let events_consumer = EventsConsumer::new(
        events_config,
        ch_writable.as_ref().clone(),
        event_deduplicator,
        state.redis.clone(),
    )?;
    
    let handle = tokio::spawn(async move {
        if let Err(e) = events_consumer.run().await {
            tracing::error!("Events consumer error: {}", e);
        }
    });
    
    tracing::info!("Events consumer spawned");
    Ok(handle)
}

/// Spawn background jobs (suggested users, trending, cache warmup)
async fn spawn_background_jobs(state: &AppState) -> Result<tokio::task::JoinHandle<()>, Box<dyn std::error::Error>> {
    use crate::jobs::{
        self, run_jobs, CacheRefreshJob, JobContext,
        suggested_users_generator::{SuggestedUsersJob, SuggestionConfig},
        trending_generator::{TrendingGeneratorJob, TrendingConfig},
        cache_warmer::{CacheWarmerJob, CacheWarmerConfig},
    };
    
    let (shutdown_tx, _) = broadcast::channel::<()>(1);
    
    let ch_client = clickhouse::Client::default()
        .with_url(&state.config.clickhouse.url)
        .with_user(&state.config.clickhouse.username)
        .with_password(&state.config.clickhouse.password)
        .with_database(&state.config.clickhouse.database);
    
    let job_ctx1 = JobContext::new(state.redis.clone(), ch_client.clone());
    let job_ctx2 = JobContext::new(state.redis.clone(), ch_client.clone());
    let job_ctx3 = JobContext::new(state.redis.clone(), ch_client);
    
    let suggested_job = SuggestedUsersJob::new(SuggestionConfig::default());
    let trending_job = TrendingGeneratorJob::new(TrendingConfig::hourly());
    let cache_warmer = CacheWarmerJob::new(CacheWarmerConfig::default());
    
    let handle = tokio::spawn(async move {
        run_jobs(
            vec![
                (Arc::new(suggested_job) as Arc<dyn CacheRefreshJob>, job_ctx1),
                (Arc::new(trending_job) as Arc<dyn CacheRefreshJob>, job_ctx2),
                (Arc::new(cache_warmer) as Arc<dyn CacheRefreshJob>, job_ctx3),
            ],
            2,
            shutdown_tx,
        ).await;
    });
    
    tracing::info!("Background jobs spawned");
    Ok(handle)
}

/// Spawn stories cleanup worker (every 5 minutes)
async fn spawn_stories_cleanup(state: &AppState) -> Result<tokio::task::JoinHandle<()>, Box<dyn std::error::Error>> {
    let db = state.db.clone();
    
    let handle = tokio::spawn(async move {
        let svc = StoriesService::new(db);
        let mut interval = tokio::time::interval(std::time::Duration::from_secs(300));
        
        loop {
            interval.tick().await;
            if let Ok(affected) = svc.cleanup_expired().await {
                if affected > 0 {
                    tracing::info!("stories cleanup marked deleted: {}", affected);
                }
            }
        }
    });
    
    tracing::info!("Stories cleanup worker spawned");
    Ok(handle)
}

/// Spawn Milvus health check
fn spawn_milvus_health_check() -> tokio::task::JoinHandle<()> {
    tokio::spawn(async {
        let cfg = video_config::VideoConfig::from_env().inference;
        let dl = DeepLearningInferenceService::new(cfg);
        
        if let Ok(true) = dl.check_milvus_health().await {
            if let Ok(true) = dl.ensure_milvus_collection().await {
                tracing::info!("Milvus collection ensured at startup");
            } else {
                tracing::warn!("Milvus collection ensure failed");
            }
        } else {
            tracing::warn!("Milvus not healthy at startup; using PG fallback");
        }
    })
}
