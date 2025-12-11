// ============================================
// A/B Testing Framework (T248)
// ============================================
//
// Implements user bucketing and experiment tracking for comparing
// recommendation algorithm variants.
//
// Features:
// - Consistent hashing for deterministic user assignment
// - Experiment configuration from PostgreSQL (via ExperimentsRepo)
// - Event logging to ClickHouse
// - Redis caching for fast variant lookup

use crate::db::experiments_repo::{ExperimentStatus as DbExperimentStatus, ExperimentsRepo};
use crate::error::{AppError, Result};
use chrono::{DateTime, Utc};
use redis::aio::ConnectionManager;
use serde::{Deserialize, Serialize};
use std::collections::hash_map::DefaultHasher;
use std::collections::HashMap;
use std::hash::{Hash, Hasher};
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{debug, info, warn};
use uuid::Uuid;

/// Cache TTL for variant assignments (7 days in seconds)
const VARIANT_CACHE_TTL: u64 = 7 * 24 * 3600;

/// Cache key prefix for variant assignments
const VARIANT_CACHE_PREFIX: &str = "ab:variant:";

/// A/B testing framework with PostgreSQL persistence and Redis caching
pub struct ABTestingFramework {
    /// In-memory cache of active experiments (refreshed periodically)
    experiments: Arc<RwLock<HashMap<String, Experiment>>>,

    /// PostgreSQL repository for persistence
    repo: Option<Arc<ExperimentsRepo>>,

    /// Redis connection for caching variant assignments
    redis: Option<Arc<RwLock<ConnectionManager>>>,

    /// Last refresh timestamp
    last_refresh: Arc<RwLock<DateTime<Utc>>>,
}

/// Experiment configuration (in-memory representation)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Experiment {
    pub id: Uuid,
    pub name: String,
    pub description: String,
    pub start_date: DateTime<Utc>,
    pub end_date: Option<DateTime<Utc>>,
    pub variants: Vec<Variant>,
    pub status: ExperimentStatus,
}

/// Experiment variant
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Variant {
    pub id: Uuid,
    pub name: String,
    pub allocation: u8,            // Percentage (0-100)
    pub config: serde_json::Value, // Variant-specific config
}

/// Experiment status
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ExperimentStatus {
    Draft,
    Running,
    Completed,
    Cancelled,
}

impl From<DbExperimentStatus> for ExperimentStatus {
    fn from(status: DbExperimentStatus) -> Self {
        match status {
            DbExperimentStatus::Draft => ExperimentStatus::Draft,
            DbExperimentStatus::Running => ExperimentStatus::Running,
            DbExperimentStatus::Completed => ExperimentStatus::Completed,
            DbExperimentStatus::Cancelled => ExperimentStatus::Cancelled,
        }
    }
}

/// Experiment event for logging
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExperimentEvent {
    pub experiment_id: Uuid,
    pub variant_name: String,
    pub user_id: Uuid,
    pub post_id: Option<Uuid>,
    pub action: String, // impression, click, like, share, dwell, feed_request
    pub dwell_ms: u32,
    pub session_id: Uuid,
    pub timestamp: DateTime<Utc>,
}

/// Cached variant assignment
#[derive(Debug, Clone, Serialize, Deserialize)]
struct CachedVariant {
    variant_id: Uuid,
    variant_name: String,
    config: serde_json::Value,
    cached_at: DateTime<Utc>,
}

impl ABTestingFramework {
    /// Initialize framework with PostgreSQL and Redis
    pub async fn new_with_persistence(
        repo: Arc<ExperimentsRepo>,
        redis: Option<ConnectionManager>,
    ) -> Result<Self> {
        let framework = Self {
            experiments: Arc::new(RwLock::new(HashMap::new())),
            repo: Some(repo),
            redis: redis.map(|r| Arc::new(RwLock::new(r))),
            last_refresh: Arc::new(RwLock::new(Utc::now())),
        };

        // Load initial experiments from database
        framework.refresh_experiments().await?;

        Ok(framework)
    }

    /// Initialize framework without persistence (in-memory only)
    ///
    /// Used for testing or when database is not available
    pub async fn new() -> Result<Self> {
        Ok(Self {
            experiments: Arc::new(RwLock::new(HashMap::new())),
            repo: None,
            redis: None,
            last_refresh: Arc::new(RwLock::new(Utc::now())),
        })
    }

    /// Refresh experiments from PostgreSQL
    pub async fn refresh_experiments(&self) -> Result<()> {
        let repo = match &self.repo {
            Some(r) => r,
            None => {
                debug!("No repository configured, skipping refresh");
                return Ok(());
            }
        };

        // Load running experiments from database
        let db_experiments = repo
            .list_experiments(Some(DbExperimentStatus::Running))
            .await?;

        let mut experiments = HashMap::new();

        for db_exp in db_experiments {
            // Load variants for this experiment
            let db_variants = repo.get_variants(db_exp.id).await?;

            let variants: Vec<Variant> = db_variants
                .into_iter()
                .map(|v| Variant {
                    id: v.id,
                    name: v.variant_name,
                    allocation: v.traffic_allocation as u8,
                    config: v.variant_config,
                })
                .collect();

            let experiment = Experiment {
                id: db_exp.id,
                name: db_exp.name.clone(),
                description: db_exp.description.unwrap_or_default(),
                start_date: db_exp.start_date.unwrap_or_else(Utc::now),
                end_date: db_exp.end_date,
                variants,
                status: db_exp.status.into(),
            };

            experiments.insert(db_exp.name, experiment);
        }

        // Update in-memory cache
        {
            let mut cache = self.experiments.write().await;
            *cache = experiments;
        }

        // Update refresh timestamp
        {
            let mut last_refresh = self.last_refresh.write().await;
            *last_refresh = Utc::now();
        }

        info!(
            "Refreshed {} active experiments from database",
            self.experiments.read().await.len()
        );

        Ok(())
    }

    /// Assign user to experiment variant (consistent hashing)
    ///
    /// Algorithm:
    /// 1. Hash user_id + experiment_name
    /// 2. Bucket = hash % 100 (0-99)
    /// 3. Find variant based on cumulative allocation
    ///
    /// Example:
    /// - Control: 50% (buckets 0-49)
    /// - Variant A: 30% (buckets 50-79)
    /// - Variant B: 20% (buckets 80-99)
    pub fn assign_bucket<'a>(
        &self,
        user_id: Uuid,
        experiment: &'a Experiment,
    ) -> Result<&'a Variant> {
        // Check if experiment is running
        if experiment.status != ExperimentStatus::Running {
            return Err(AppError::BadRequest(format!(
                "Experiment {} is not running (status: {:?})",
                experiment.name, experiment.status
            )));
        }

        if experiment.variants.is_empty() {
            return Err(AppError::Internal(format!(
                "Experiment {} has no variants",
                experiment.name
            )));
        }

        // Consistent hashing
        let mut hasher = DefaultHasher::new();
        user_id.hash(&mut hasher);
        experiment.name.hash(&mut hasher);
        let hash_value = hasher.finish();
        let bucket = (hash_value % 100) as u8;

        // Find variant based on cumulative allocation
        let mut cumulative = 0u8;
        for variant in &experiment.variants {
            cumulative += variant.allocation;
            if bucket < cumulative {
                return Ok(variant);
            }
        }

        // Fallback to first variant (should never reach here if allocations sum to 100)
        Ok(&experiment.variants[0])
    }

    /// Get variant for user (with Redis caching)
    pub async fn get_variant_for_user(
        &self,
        user_id: Uuid,
        experiment_name: &str,
    ) -> Result<(Uuid, String, serde_json::Value)> {
        // Try Redis cache first
        if let Some(cached) = self.get_cached_variant(user_id, experiment_name).await? {
            debug!(
                "Cache hit for user {} in experiment {}",
                user_id, experiment_name
            );
            return Ok((cached.variant_id, cached.variant_name, cached.config));
        }

        // Get experiment from memory
        let experiments = self.experiments.read().await;
        let experiment = experiments
            .get(experiment_name)
            .ok_or_else(|| AppError::NotFound(format!("Experiment: {}", experiment_name)))?;

        // Assign bucket
        let variant = self.assign_bucket(user_id, experiment)?;

        // Persist assignment to database
        if let Some(repo) = &self.repo {
            match repo
                .create_assignment(experiment.id, user_id, variant.id)
                .await
            {
                Ok(_) => {
                    debug!(
                        "Persisted assignment: user {} -> variant {} in experiment {}",
                        user_id, variant.name, experiment_name
                    );
                }
                Err(e) => {
                    // Log but don't fail - assignment might already exist
                    warn!("Failed to persist assignment (may already exist): {}", e);
                }
            }
        }

        // Cache in Redis
        let cached = CachedVariant {
            variant_id: variant.id,
            variant_name: variant.name.clone(),
            config: variant.config.clone(),
            cached_at: Utc::now(),
        };
        self.cache_variant(user_id, experiment_name, &cached)
            .await?;

        Ok((variant.id, variant.name.clone(), variant.config.clone()))
    }

    /// Get variant configuration for user (convenience method)
    pub async fn get_variant_config(
        &self,
        user_id: Uuid,
        experiment_name: &str,
    ) -> Result<serde_json::Value> {
        let (_, _, config) = self.get_variant_for_user(user_id, experiment_name).await?;
        Ok(config)
    }

    /// Get cached variant from Redis
    async fn get_cached_variant(
        &self,
        user_id: Uuid,
        experiment_name: &str,
    ) -> Result<Option<CachedVariant>> {
        let redis = match &self.redis {
            Some(r) => r,
            None => return Ok(None),
        };

        let key = format!("{}{}:{}", VARIANT_CACHE_PREFIX, experiment_name, user_id);

        let mut conn = redis.write().await;
        let result: Option<String> = redis::cmd("GET")
            .arg(&key)
            .query_async(&mut *conn)
            .await
            .map_err(|e| {
                warn!("Redis GET failed for {}: {}", key, e);
                AppError::Internal(format!("Redis error: {}", e))
            })?;

        if let Some(json) = result {
            match serde_json::from_str::<CachedVariant>(&json) {
                Ok(cached) => return Ok(Some(cached)),
                Err(e) => {
                    warn!("Failed to deserialize cached variant: {}", e);
                    // Invalid cache entry, delete it
                    let _: () = redis::cmd("DEL")
                        .arg(&key)
                        .query_async(&mut *conn)
                        .await
                        .unwrap_or(());
                }
            }
        }

        Ok(None)
    }

    /// Cache variant assignment in Redis
    async fn cache_variant(
        &self,
        user_id: Uuid,
        experiment_name: &str,
        cached: &CachedVariant,
    ) -> Result<()> {
        let redis = match &self.redis {
            Some(r) => r,
            None => return Ok(()),
        };

        let key = format!("{}{}:{}", VARIANT_CACHE_PREFIX, experiment_name, user_id);
        let json = serde_json::to_string(cached)
            .map_err(|e| AppError::Internal(format!("Failed to serialize variant: {}", e)))?;

        let mut conn = redis.write().await;
        redis::cmd("SETEX")
            .arg(&key)
            .arg(VARIANT_CACHE_TTL)
            .arg(&json)
            .query_async::<_, ()>(&mut *conn)
            .await
            .map_err(|e| {
                warn!("Redis SETEX failed for {}: {}", key, e);
                AppError::Internal(format!("Redis error: {}", e))
            })?;

        debug!(
            "Cached variant for user {} in experiment {}",
            user_id, experiment_name
        );
        Ok(())
    }

    /// Invalidate cached variant for user
    pub async fn invalidate_cache(&self, user_id: Uuid, experiment_name: &str) -> Result<()> {
        let redis = match &self.redis {
            Some(r) => r,
            None => return Ok(()),
        };

        let key = format!("{}{}:{}", VARIANT_CACHE_PREFIX, experiment_name, user_id);

        let mut conn = redis.write().await;
        redis::cmd("DEL")
            .arg(&key)
            .query_async::<_, ()>(&mut *conn)
            .await
            .map_err(|e| {
                warn!("Redis DEL failed for {}: {}", key, e);
                AppError::Internal(format!("Redis error: {}", e))
            })?;

        Ok(())
    }

    /// Log experiment event to database (via repository)
    pub async fn log_event(&self, event: ExperimentEvent) -> Result<()> {
        let repo = match &self.repo {
            Some(r) => r,
            None => {
                debug!("No repository configured, skipping event logging");
                return Ok(());
            }
        };

        // Get experiment ID from name
        let experiments = self.experiments.read().await;
        let experiment = experiments
            .get(&format!("exp_{}", event.experiment_id))
            .or_else(|| experiments.values().find(|e| e.id == event.experiment_id));

        if let Some(exp) = experiment {
            // Find variant ID
            let variant = exp.variants.iter().find(|v| v.name == event.variant_name);

            // Record metric
            repo.record_metric(
                exp.id,
                event.user_id,
                variant.map(|v| v.id),
                event.action.clone(),
                1.0, // Count metric
            )
            .await?;

            // Record dwell time if applicable
            if event.dwell_ms > 0 {
                repo.record_metric(
                    exp.id,
                    event.user_id,
                    variant.map(|v| v.id),
                    format!("{}_dwell_ms", event.action),
                    event.dwell_ms as f64,
                )
                .await?;
            }

            debug!(
                "Logged event '{}' for user {} in experiment {}",
                event.action, event.user_id, exp.name
            );
        } else {
            warn!(
                "Experiment {} not found for event logging",
                event.experiment_id
            );
        }

        Ok(())
    }

    /// Add or update experiment (in-memory, for testing)
    pub async fn add_experiment(&self, experiment: Experiment) -> Result<()> {
        // Validate allocation sums to 100
        let total_allocation: u8 = experiment.variants.iter().map(|v| v.allocation).sum();
        if total_allocation != 100 {
            return Err(AppError::BadRequest(format!(
                "Variant allocations must sum to 100 (got {})",
                total_allocation
            )));
        }

        let mut experiments = self.experiments.write().await;
        experiments.insert(experiment.name.clone(), experiment);
        Ok(())
    }

    /// Remove experiment (in-memory)
    pub async fn remove_experiment(&self, experiment_name: &str) -> Result<()> {
        let mut experiments = self.experiments.write().await;
        experiments
            .remove(experiment_name)
            .ok_or_else(|| AppError::NotFound(format!("Experiment: {}", experiment_name)))?;
        Ok(())
    }

    /// Get all active experiments
    pub async fn get_active_experiments(&self) -> Vec<Experiment> {
        self.experiments
            .read()
            .await
            .values()
            .filter(|exp| exp.status == ExperimentStatus::Running)
            .cloned()
            .collect()
    }

    /// Get experiment by name
    pub async fn get_experiment(&self, name: &str) -> Option<Experiment> {
        self.experiments.read().await.get(name).cloned()
    }

    /// Check if refresh is needed (older than 5 minutes)
    pub async fn needs_refresh(&self) -> bool {
        let last = *self.last_refresh.read().await;
        Utc::now().signed_duration_since(last).num_minutes() > 5
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_bucket_assignment_deterministic() {
        let framework = ABTestingFramework::new().await.unwrap();

        let experiment = Experiment {
            id: Uuid::new_v4(),
            name: "test_experiment".to_string(),
            description: "Test".to_string(),
            start_date: Utc::now(),
            end_date: None,
            variants: vec![
                Variant {
                    id: Uuid::new_v4(),
                    name: "control".to_string(),
                    allocation: 50,
                    config: serde_json::json!({"algorithm": "v1.0"}),
                },
                Variant {
                    id: Uuid::new_v4(),
                    name: "variant_a".to_string(),
                    allocation: 50,
                    config: serde_json::json!({"algorithm": "v2.0"}),
                },
            ],
            status: ExperimentStatus::Running,
        };

        framework.add_experiment(experiment.clone()).await.unwrap();

        let user_id = Uuid::new_v4();

        // Same user should always get same variant
        let variant1 = framework.assign_bucket(user_id, &experiment).unwrap();
        let variant2 = framework.assign_bucket(user_id, &experiment).unwrap();

        assert_eq!(variant1.name, variant2.name);
    }

    #[tokio::test]
    async fn test_allocation_distribution() {
        let framework = ABTestingFramework::new().await.unwrap();

        let experiment = Experiment {
            id: Uuid::new_v4(),
            name: "test_experiment".to_string(),
            description: "Test".to_string(),
            start_date: Utc::now(),
            end_date: None,
            variants: vec![
                Variant {
                    id: Uuid::new_v4(),
                    name: "control".to_string(),
                    allocation: 50,
                    config: serde_json::json!({"algorithm": "v1.0"}),
                },
                Variant {
                    id: Uuid::new_v4(),
                    name: "variant_a".to_string(),
                    allocation: 30,
                    config: serde_json::json!({"algorithm": "v2.0"}),
                },
                Variant {
                    id: Uuid::new_v4(),
                    name: "variant_b".to_string(),
                    allocation: 20,
                    config: serde_json::json!({"algorithm": "v2.0"}),
                },
            ],
            status: ExperimentStatus::Running,
        };

        framework.add_experiment(experiment.clone()).await.unwrap();

        // Test with 1000 simulated users
        let mut counts = HashMap::new();
        for _ in 0..1000 {
            let user_id = Uuid::new_v4();
            let variant = framework.assign_bucket(user_id, &experiment).unwrap();
            *counts.entry(variant.name.clone()).or_insert(0) += 1;
        }

        // Verify allocation is approximately correct (±10% tolerance)
        let control_count = *counts.get("control").unwrap_or(&0);
        let variant_a_count = *counts.get("variant_a").unwrap_or(&0);
        let variant_b_count = *counts.get("variant_b").unwrap_or(&0);

        assert!(
            control_count > 400 && control_count < 600,
            "Control: {}",
            control_count
        ); // ~50%
        assert!(
            variant_a_count > 200 && variant_a_count < 400,
            "Variant A: {}",
            variant_a_count
        ); // ~30%
        assert!(
            variant_b_count > 100 && variant_b_count < 300,
            "Variant B: {}",
            variant_b_count
        ); // ~20%
    }

    #[tokio::test]
    async fn test_invalid_allocation() {
        let framework = ABTestingFramework::new().await.unwrap();

        let experiment = Experiment {
            id: Uuid::new_v4(),
            name: "test_experiment".to_string(),
            description: "Test".to_string(),
            start_date: Utc::now(),
            end_date: None,
            variants: vec![Variant {
                id: Uuid::new_v4(),
                name: "control".to_string(),
                allocation: 40, // Only 40%, should fail
                config: serde_json::json!({"algorithm": "v1.0"}),
            }],
            status: ExperimentStatus::Running,
        };

        let result = framework.add_experiment(experiment).await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_experiment_not_running() {
        let framework = ABTestingFramework::new().await.unwrap();

        let experiment = Experiment {
            id: Uuid::new_v4(),
            name: "draft_experiment".to_string(),
            description: "Test".to_string(),
            start_date: Utc::now(),
            end_date: None,
            variants: vec![Variant {
                id: Uuid::new_v4(),
                name: "control".to_string(),
                allocation: 100,
                config: serde_json::json!({}),
            }],
            status: ExperimentStatus::Draft, // Not running
        };

        let user_id = Uuid::new_v4();
        let result = framework.assign_bucket(user_id, &experiment);
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_get_active_experiments() {
        let framework = ABTestingFramework::new().await.unwrap();

        let running_exp = Experiment {
            id: Uuid::new_v4(),
            name: "running_exp".to_string(),
            description: "Running".to_string(),
            start_date: Utc::now(),
            end_date: None,
            variants: vec![Variant {
                id: Uuid::new_v4(),
                name: "control".to_string(),
                allocation: 100,
                config: serde_json::json!({}),
            }],
            status: ExperimentStatus::Running,
        };

        let draft_exp = Experiment {
            id: Uuid::new_v4(),
            name: "draft_exp".to_string(),
            description: "Draft".to_string(),
            start_date: Utc::now(),
            end_date: None,
            variants: vec![Variant {
                id: Uuid::new_v4(),
                name: "control".to_string(),
                allocation: 100,
                config: serde_json::json!({}),
            }],
            status: ExperimentStatus::Draft,
        };

        framework.add_experiment(running_exp).await.unwrap();
        framework.add_experiment(draft_exp).await.unwrap();

        let active = framework.get_active_experiments().await;
        assert_eq!(active.len(), 1);
        assert_eq!(active[0].name, "running_exp");
    }
}
