/// Metrics Service - Event recording and aggregation for experiments
use crate::db::experiment_repo::{
    get_cached_results, get_experiment_metrics_aggregated, record_metric, upsert_results_cache,
    AggregatedMetric, ExperimentResultsCache,
};
use redis::AsyncCommands;
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use std::collections::HashMap;
use std::sync::Arc;
use uuid::Uuid;

const METRIC_COUNTER_PREFIX: &str = "exp:metric:counter";
const BATCH_SIZE: usize = 100;

#[derive(Clone)]
pub struct MetricsService {
    pool: Arc<PgPool>,
    redis: Arc<redis::Client>,
}

/// Experiment results by variant
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExperimentResults {
    pub experiment_id: Uuid,
    pub status: String,
    pub variants: HashMap<String, VariantMetrics>,
}

/// Metrics for a single variant
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VariantMetrics {
    pub sample_size: i64,
    pub metrics: HashMap<String, MetricStats>,
}

/// Statistics for a metric
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MetricStats {
    pub mean: f64,
    pub std_dev: Option<f64>,
    pub sum: Option<f64>,
}

impl MetricsService {
    pub fn new(pool: Arc<PgPool>, redis: Arc<redis::Client>) -> Self {
        Self { pool, redis }
    }

    /// Record a metric event (async, non-blocking)
    pub async fn record_metric(
        &self,
        experiment_id: Uuid,
        user_id: Uuid,
        variant_id: Option<Uuid>,
        metric_name: &str,
        metric_value: f64,
    ) -> Result<(), MetricsError> {
        // 1. Write to database (primary source of truth)
        record_metric(
            &self.pool,
            experiment_id,
            user_id,
            variant_id,
            metric_name,
            metric_value,
        )
        .await?;

        // 2. Update Redis counters for real-time aggregation (best-effort)
        if let Some(vid) = variant_id {
            let _ = self
                .increment_counter(experiment_id, vid, metric_name, metric_value)
                .await;
        }

        Ok(())
    }

    /// Get experiment results (combines cached + real-time data)
    pub async fn get_experiment_results(
        &self,
        experiment_id: Uuid,
    ) -> Result<ExperimentResults, MetricsError> {
        // Get experiment status
        let experiment = crate::db::experiment_repo::get_experiment(&self.pool, experiment_id)
            .await?
            .ok_or(MetricsError::ExperimentNotFound(experiment_id))?;

        // Get aggregated metrics from database
        let aggregated = get_experiment_metrics_aggregated(&self.pool, experiment_id).await?;

        // Group by variant
        let mut variants: HashMap<String, VariantMetrics> = HashMap::new();

        for metric in aggregated {
            let variant_entry = variants
                .entry(metric.variant_name.clone())
                .or_insert_with(|| VariantMetrics {
                    sample_size: 0,
                    metrics: HashMap::new(),
                });

            variant_entry.sample_size = metric.sample_size;
            variant_entry.metrics.insert(
                metric.metric_name.clone(),
                MetricStats {
                    mean: metric.metric_mean.unwrap_or(0.0),
                    std_dev: metric.metric_std_dev,
                    sum: metric.metric_sum,
                },
            );
        }

        Ok(ExperimentResults {
            experiment_id,
            status: format!("{:?}", experiment.status).to_lowercase(),
            variants,
        })
    }

    /// Get cached results (fast, potentially stale)
    pub async fn get_cached_results(
        &self,
        experiment_id: Uuid,
    ) -> Result<Vec<ExperimentResultsCache>, MetricsError> {
        Ok(get_cached_results(&self.pool, experiment_id).await?)
    }

    /// Refresh results cache (run periodically)
    pub async fn refresh_results_cache(&self, experiment_id: Uuid) -> Result<(), MetricsError> {
        let aggregated = get_experiment_metrics_aggregated(&self.pool, experiment_id).await?;

        for metric in aggregated {
            upsert_results_cache(
                &self.pool,
                experiment_id,
                metric.variant_id,
                &metric.metric_name,
                metric.sample_size,
                metric.metric_sum.unwrap_or(0.0),
                metric.metric_mean.unwrap_or(0.0),
                metric.metric_variance,
                metric.metric_std_dev,
            )
            .await?;
        }

        tracing::info!("Refreshed results cache for experiment {}", experiment_id);
        Ok(())
    }

    /// Increment real-time counter in Redis
    async fn increment_counter(
        &self,
        experiment_id: Uuid,
        variant_id: Uuid,
        metric_name: &str,
        value: f64,
    ) -> Result<(), MetricsError> {
        let mut conn = self.redis.get_multiplexed_async_connection().await?;

        // Counter key: exp:metric:counter:{exp_id}:{variant_id}:{metric_name}:count
        let count_key = format!(
            "{}:{}:{}:{}:count",
            METRIC_COUNTER_PREFIX, experiment_id, variant_id, metric_name
        );
        let sum_key = format!(
            "{}:{}:{}:{}:sum",
            METRIC_COUNTER_PREFIX, experiment_id, variant_id, metric_name
        );

        // Increment count and sum
        conn.incr(&count_key, 1).await?;
        conn.incr(&sum_key, value).await?;

        // Set TTL (7 days)
        conn.expire(&count_key, 604800).await?;
        conn.expire(&sum_key, 604800).await?;

        Ok(())
    }

    /// Get real-time metrics from Redis
    pub async fn get_realtime_metrics(
        &self,
        experiment_id: Uuid,
        variant_id: Uuid,
        metric_name: &str,
    ) -> Result<Option<(i64, f64)>, MetricsError> {
        let mut conn = self.redis.get_multiplexed_async_connection().await?;

        let count_key = format!(
            "{}:{}:{}:{}:count",
            METRIC_COUNTER_PREFIX, experiment_id, variant_id, metric_name
        );
        let sum_key = format!(
            "{}:{}:{}:{}:sum",
            METRIC_COUNTER_PREFIX, experiment_id, variant_id, metric_name
        );

        let count: Option<i64> = conn.get(&count_key).await?;
        let sum: Option<f64> = conn.get(&sum_key).await?;

        match (count, sum) {
            (Some(c), Some(s)) => Ok(Some((c, s))),
            _ => Ok(None),
        }
    }

    /// Clear real-time metrics for experiment
    pub async fn clear_realtime_metrics(&self, experiment_id: Uuid) -> Result<(), MetricsError> {
        let mut conn = self.redis.get_multiplexed_async_connection().await?;
        let pattern = format!("{}:{}:*", METRIC_COUNTER_PREFIX, experiment_id);

        // Scan and delete
        let mut cursor = 0;
        loop {
            let (new_cursor, keys): (u64, Vec<String>) = redis::cmd("SCAN")
                .arg(cursor)
                .arg("MATCH")
                .arg(&pattern)
                .arg("COUNT")
                .arg(100)
                .query_async(&mut conn)
                .await?;

            if !keys.is_empty() {
                redis::cmd("DEL")
                    .arg(&keys)
                    .query_async::<_, ()>(&mut conn)
                    .await?;
            }

            cursor = new_cursor;
            if cursor == 0 {
                break;
            }
        }

        tracing::info!("Cleared realtime metrics for experiment {}", experiment_id);
        Ok(())
    }

    /// Batch record metrics (for high-throughput scenarios)
    pub async fn record_metrics_batch(
        &self,
        records: Vec<MetricRecord>,
    ) -> Result<(), MetricsError> {
        // Insert in batches to avoid overwhelming the database
        for chunk in records.chunks(BATCH_SIZE) {
            let mut tx = self.pool.begin().await?;

            for record in chunk {
                sqlx::query(
                    r#"
                    INSERT INTO experiment_metrics (experiment_id, user_id, variant_id, metric_name, metric_value)
                    VALUES ($1, $2, $3, $4, $5)
                    "#,
                )
                .bind(record.experiment_id)
                .bind(record.user_id)
                .bind(record.variant_id)
                .bind(&record.metric_name)
                .bind(record.metric_value)
                .execute(&mut *tx)
                .await?;
            }

            tx.commit().await?;
        }

        tracing::info!("Batch recorded {} metrics", records.len());
        Ok(())
    }
}

/// Metric record for batch operations
#[derive(Debug, Clone)]
pub struct MetricRecord {
    pub experiment_id: Uuid,
    pub user_id: Uuid,
    pub variant_id: Option<Uuid>,
    pub metric_name: String,
    pub metric_value: f64,
}

/// Metrics service errors
#[derive(Debug, thiserror::Error)]
pub enum MetricsError {
    #[error("Experiment not found: {0}")]
    ExperimentNotFound(Uuid),

    #[error("Database error: {0}")]
    DatabaseError(#[from] sqlx::Error),

    #[error("Redis error: {0}")]
    RedisError(#[from] redis::RedisError),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_metric_stats_calculation() {
        // Test data
        let metrics = vec![
            AggregatedMetric {
                variant_id: Uuid::new_v4(),
                variant_name: "control".to_string(),
                metric_name: "click_rate".to_string(),
                sample_size: 100,
                metric_sum: Some(25.0),
                metric_mean: Some(0.25),
                metric_variance: Some(0.01),
                metric_std_dev: Some(0.1),
            },
            AggregatedMetric {
                variant_id: Uuid::new_v4(),
                variant_name: "treatment".to_string(),
                metric_name: "click_rate".to_string(),
                sample_size: 100,
                metric_sum: Some(35.0),
                metric_mean: Some(0.35),
                metric_variance: Some(0.015),
                metric_std_dev: Some(0.12),
            },
        ];

        // Verify calculations
        assert_eq!(metrics[0].sample_size, 100);
        assert_eq!(metrics[0].metric_mean, Some(0.25));
        assert_eq!(metrics[1].metric_mean, Some(0.35));
    }

    #[test]
    fn test_batch_chunking() {
        let records: Vec<MetricRecord> = (0..250)
            .map(|i| MetricRecord {
                experiment_id: Uuid::new_v4(),
                user_id: Uuid::new_v4(),
                variant_id: Some(Uuid::new_v4()),
                metric_name: format!("metric_{}", i),
                metric_value: i as f64,
            })
            .collect();

        let chunks: Vec<_> = records.chunks(BATCH_SIZE).collect();
        assert_eq!(chunks.len(), 3, "Should have 3 batches (100, 100, 50)");
        assert_eq!(chunks[0].len(), 100);
        assert_eq!(chunks[1].len(), 100);
        assert_eq!(chunks[2].len(), 50);
    }
}
