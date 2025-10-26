/// Assignment Service - Deterministic variant assignment with Redis caching
use crate::db::experiment_repo::{
    create_assignment, get_assignment, get_experiment, get_experiment_variants, Experiment,
    ExperimentAssignment, ExperimentStatus, ExperimentVariant,
};
use redis::AsyncCommands;
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};
use std::sync::Arc;
use uuid::Uuid;

const ASSIGNMENT_CACHE_TTL: u64 = 86400; // 24 hours

#[derive(Clone)]
pub struct AssignmentService {
    pool: Arc<PgPool>,
    redis: Arc<redis::Client>,
}

/// Assignment response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AssignmentResponse {
    pub experiment_id: Uuid,
    pub user_id: Uuid,
    pub variant_id: Uuid,
    pub variant_name: String,
    pub config: serde_json::Value,
}

impl AssignmentService {
    pub fn new(pool: Arc<PgPool>, redis: Arc<redis::Client>) -> Self {
        Self { pool, redis }
    }

    /// Assign a user to a variant (deterministic, cached)
    pub async fn assign_variant(
        &self,
        experiment_id: Uuid,
        user_id: Uuid,
    ) -> Result<AssignmentResponse, AssignmentError> {
        // 1. Check cache first
        let cache_key = format!("exp:assign:{}:{}", experiment_id, user_id);
        if let Ok(cached) = self.get_from_cache(&cache_key).await {
            tracing::debug!(
                "Assignment cache hit for user {} in experiment {}",
                user_id,
                experiment_id
            );
            return Ok(cached);
        }

        // 2. Check database for existing assignment
        if let Some(existing) = get_assignment(&self.pool, experiment_id, user_id).await? {
            let response = self.build_response(existing).await?;
            self.cache_assignment(&cache_key, &response).await?;
            return Ok(response);
        }

        // 3. Get experiment details
        let experiment = get_experiment(&self.pool, experiment_id)
            .await?
            .ok_or(AssignmentError::ExperimentNotFound(experiment_id))?;

        // 4. Validate experiment is running
        if !matches!(experiment.status, ExperimentStatus::Running) {
            return Err(AssignmentError::ExperimentNotRunning(experiment_id));
        }

        // 5. Check if user falls within sample (deterministic)
        if !self.is_user_sampled(experiment_id, user_id, experiment.sample_size) {
            return Err(AssignmentError::UserNotSampled);
        }

        // 6. Get variants
        let variants = get_experiment_variants(&self.pool, experiment_id).await?;
        if variants.is_empty() {
            return Err(AssignmentError::NoVariants(experiment_id));
        }

        // 7. Determine variant using deterministic hashing
        let variant = self.select_variant(experiment_id, user_id, &variants);

        // 8. Create assignment in database
        let assignment = create_assignment(&self.pool, experiment_id, user_id, variant.id).await?;

        // 9. Build response
        let response = AssignmentResponse {
            experiment_id: assignment.experiment_id,
            user_id: assignment.user_id,
            variant_id: assignment.variant_id,
            variant_name: variant.variant_name.clone(),
            config: variant.variant_config.clone(),
        };

        // 10. Cache result
        self.cache_assignment(&cache_key, &response).await?;

        tracing::info!(
            "Assigned user {} to variant '{}' in experiment {}",
            user_id,
            variant.variant_name,
            experiment.name
        );

        Ok(response)
    }

    /// Get existing assignment (from cache or DB)
    pub async fn get_assignment(
        &self,
        experiment_id: Uuid,
        user_id: Uuid,
    ) -> Result<Option<AssignmentResponse>, AssignmentError> {
        // Check cache
        let cache_key = format!("exp:assign:{}:{}", experiment_id, user_id);
        if let Ok(cached) = self.get_from_cache(&cache_key).await {
            return Ok(Some(cached));
        }

        // Check database
        if let Some(assignment) = get_assignment(&self.pool, experiment_id, user_id).await? {
            let response = self.build_response(assignment).await?;
            self.cache_assignment(&cache_key, &response).await?;
            return Ok(Some(response));
        }

        Ok(None)
    }

    /// Check if user falls within sample using deterministic hashing
    fn is_user_sampled(&self, experiment_id: Uuid, user_id: Uuid, sample_size: i32) -> bool {
        if sample_size == 100 {
            return true;
        }
        if sample_size == 0 {
            return false;
        }

        // Hash experiment_id + user_id for deterministic sampling
        let hash = self.compute_hash(&format!("sample:{}:{}", experiment_id, user_id));
        let bucket = (hash % 100) as i32;

        bucket < sample_size
    }

    /// Select variant using deterministic hashing and traffic allocation
    fn select_variant<'a>(
        &self,
        experiment_id: Uuid,
        user_id: Uuid,
        variants: &'a [ExperimentVariant],
    ) -> &'a ExperimentVariant {
        // Hash for variant selection (different from sampling hash)
        let hash = self.compute_hash(&format!("variant:{}:{}", experiment_id, user_id));
        let bucket = (hash % 100) as i32;

        // Find variant based on cumulative traffic allocation
        let mut cumulative = 0;
        for variant in variants {
            cumulative += variant.traffic_allocation;
            if bucket < cumulative {
                return variant;
            }
        }

        // Fallback to last variant (should never happen if allocation sums to 100)
        &variants[variants.len() - 1]
    }

    /// Compute deterministic hash
    fn compute_hash(&self, input: &str) -> u64 {
        let mut hasher = DefaultHasher::new();
        input.hash(&mut hasher);
        hasher.finish()
    }

    /// Build response from assignment
    async fn build_response(
        &self,
        assignment: ExperimentAssignment,
    ) -> Result<AssignmentResponse, AssignmentError> {
        let variant = crate::db::experiment_repo::get_variant(&self.pool, assignment.variant_id)
            .await?
            .ok_or(AssignmentError::VariantNotFound(assignment.variant_id))?;

        Ok(AssignmentResponse {
            experiment_id: assignment.experiment_id,
            user_id: assignment.user_id,
            variant_id: assignment.variant_id,
            variant_name: variant.variant_name,
            config: variant.variant_config,
        })
    }

    /// Cache assignment in Redis
    async fn cache_assignment(
        &self,
        cache_key: &str,
        response: &AssignmentResponse,
    ) -> Result<(), AssignmentError> {
        let mut conn = self.redis.get_multiplexed_async_connection().await?;
        let serialized = serde_json::to_string(response)?;
        conn.set_ex(cache_key, serialized, ASSIGNMENT_CACHE_TTL)
            .await?;
        Ok(())
    }

    /// Get assignment from cache
    async fn get_from_cache(&self, cache_key: &str) -> Result<AssignmentResponse, AssignmentError> {
        let mut conn = self.redis.get_multiplexed_async_connection().await?;
        let cached: Option<String> = conn.get(cache_key).await?;

        match cached {
            Some(data) => Ok(serde_json::from_str(&data)?),
            None => Err(AssignmentError::CacheMiss),
        }
    }

    /// Invalidate cache for experiment (called when experiment stops)
    pub async fn invalidate_experiment_cache(
        &self,
        experiment_id: Uuid,
    ) -> Result<(), AssignmentError> {
        let mut conn = self.redis.get_multiplexed_async_connection().await?;
        let pattern = format!("exp:assign:{}:*", experiment_id);

        // Scan and delete matching keys (safe for production)
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

        tracing::info!(
            "Invalidated assignment cache for experiment {}",
            experiment_id
        );
        Ok(())
    }
}

/// Assignment service errors
#[derive(Debug, thiserror::Error)]
pub enum AssignmentError {
    #[error("Experiment not found: {0}")]
    ExperimentNotFound(Uuid),

    #[error("Experiment not running: {0}")]
    ExperimentNotRunning(Uuid),

    #[error("User not in sample")]
    UserNotSampled,

    #[error("No variants defined for experiment: {0}")]
    NoVariants(Uuid),

    #[error("Variant not found: {0}")]
    VariantNotFound(Uuid),

    #[error("Cache miss")]
    CacheMiss,

    #[error("Database error: {0}")]
    DatabaseError(#[from] sqlx::Error),

    #[error("Redis error: {0}")]
    RedisError(#[from] redis::RedisError),

    #[error("Serialization error: {0}")]
    SerializationError(#[from] serde_json::Error),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_compute_hash_deterministic() {
        let service = AssignmentService {
            pool: Arc::new(PgPool::connect_lazy("").unwrap()),
            redis: Arc::new(redis::Client::open("redis://localhost").unwrap()),
        };

        let hash1 = service.compute_hash("test:123:456");
        let hash2 = service.compute_hash("test:123:456");
        assert_eq!(hash1, hash2, "Hash should be deterministic");

        let hash3 = service.compute_hash("test:123:789");
        assert_ne!(
            hash1, hash3,
            "Different inputs should produce different hashes"
        );
    }

    #[test]
    fn test_is_user_sampled_100_percent() {
        let service = AssignmentService {
            pool: Arc::new(PgPool::connect_lazy("").unwrap()),
            redis: Arc::new(redis::Client::open("redis://localhost").unwrap()),
        };

        let exp_id = Uuid::new_v4();
        let user_id = Uuid::new_v4();

        assert!(service.is_user_sampled(exp_id, user_id, 100));
    }

    #[test]
    fn test_is_user_sampled_0_percent() {
        let service = AssignmentService {
            pool: Arc::new(PgPool::connect_lazy("").unwrap()),
            redis: Arc::new(redis::Client::open("redis://localhost").unwrap()),
        };

        let exp_id = Uuid::new_v4();
        let user_id = Uuid::new_v4();

        assert!(!service.is_user_sampled(exp_id, user_id, 0));
    }

    #[test]
    fn test_select_variant_distribution() {
        let service = AssignmentService {
            pool: Arc::new(PgPool::connect_lazy("").unwrap()),
            redis: Arc::new(redis::Client::open("redis://localhost").unwrap()),
        };

        let exp_id = Uuid::new_v4();
        let variants = vec![
            ExperimentVariant {
                id: Uuid::new_v4(),
                experiment_id: exp_id,
                variant_name: "control".to_string(),
                variant_config: serde_json::json!({}),
                traffic_allocation: 50,
                created_at: chrono::Utc::now(),
            },
            ExperimentVariant {
                id: Uuid::new_v4(),
                experiment_id: exp_id,
                variant_name: "treatment".to_string(),
                variant_config: serde_json::json!({}),
                traffic_allocation: 50,
                created_at: chrono::Utc::now(),
            },
        ];

        // Test deterministic selection
        let user_id = Uuid::new_v4();
        let variant1 = service.select_variant(exp_id, user_id, &variants);
        let variant2 = service.select_variant(exp_id, user_id, &variants);
        assert_eq!(
            variant1.id, variant2.id,
            "Same user should get same variant"
        );
    }

    #[test]
    fn test_select_variant_traffic_allocation() {
        let service = AssignmentService {
            pool: Arc::new(PgPool::connect_lazy("").unwrap()),
            redis: Arc::new(redis::Client::open("redis://localhost").unwrap()),
        };

        let exp_id = Uuid::new_v4();
        let variants = vec![
            ExperimentVariant {
                id: Uuid::new_v4(),
                experiment_id: exp_id,
                variant_name: "control".to_string(),
                variant_config: serde_json::json!({}),
                traffic_allocation: 25,
                created_at: chrono::Utc::now(),
            },
            ExperimentVariant {
                id: Uuid::new_v4(),
                experiment_id: exp_id,
                variant_name: "treatment_a".to_string(),
                variant_config: serde_json::json!({}),
                traffic_allocation: 25,
                created_at: chrono::Utc::now(),
            },
            ExperimentVariant {
                id: Uuid::new_v4(),
                experiment_id: exp_id,
                variant_name: "treatment_b".to_string(),
                variant_config: serde_json::json!({}),
                traffic_allocation: 50,
                created_at: chrono::Utc::now(),
            },
        ];

        // Simulate 1000 users and check distribution
        let mut counts = std::collections::HashMap::new();
        for i in 0..1000 {
            let user_id = Uuid::from_u128(i);
            let variant = service.select_variant(exp_id, user_id, &variants);
            *counts.entry(variant.variant_name.clone()).or_insert(0) += 1;
        }

        // Allow 10% deviation from expected distribution
        let control_count = counts.get("control").unwrap_or(&0);
        let treatment_a_count = counts.get("treatment_a").unwrap_or(&0);
        let treatment_b_count = counts.get("treatment_b").unwrap_or(&0);

        assert!(
            (*control_count as f64 - 250.0).abs() < 50.0,
            "Control should be ~25% (got {})",
            control_count
        );
        assert!(
            (*treatment_a_count as f64 - 250.0).abs() < 50.0,
            "Treatment A should be ~25% (got {})",
            treatment_a_count
        );
        assert!(
            (*treatment_b_count as f64 - 500.0).abs() < 100.0,
            "Treatment B should be ~50% (got {})",
            treatment_b_count
        );
    }
}
