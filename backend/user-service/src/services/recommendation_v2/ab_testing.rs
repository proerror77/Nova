// ============================================
// A/B Testing Framework (T248)
// ============================================
//
// Implements user bucketing and experiment tracking for comparing
// recommendation algorithm variants.
//
// Features:
// - Consistent hashing for deterministic user assignment
// - Experiment configuration from PostgreSQL
// - Event logging to ClickHouse
// - Redis caching for fast variant lookup

use crate::error::{AppError, Result};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::hash_map::DefaultHasher;
use std::collections::HashMap;
use std::hash::{Hash, Hasher};
use uuid::Uuid;

/// A/B testing framework
pub struct ABTestingFramework {
    /// Active experiments loaded from PostgreSQL
    pub experiments: HashMap<String, Experiment>,
    // Redis client for caching variant assignments (optional)
    // pub redis_client: Arc<Redis>,
}

/// Experiment configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Experiment {
    pub id: u32,
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

/// Experiment event for logging
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExperimentEvent {
    pub experiment_id: u32,
    pub variant_name: String,
    pub user_id: Uuid,
    pub post_id: Option<Uuid>,
    pub action: String, // impression, click, like, share, dwell, feed_request
    pub dwell_ms: u32,
    pub session_id: Uuid,
    pub timestamp: DateTime<Utc>,
}

impl ABTestingFramework {
    /// Initialize framework (load experiments from PostgreSQL)
    pub async fn new() -> Result<Self> {
        // TODO: Load experiments from PostgreSQL
        // let experiments = load_experiments_from_db().await?;

        Ok(Self {
            experiments: HashMap::new(),
        })
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
    pub fn assign_bucket(&self, user_id: Uuid, experiment_name: &str) -> Result<String> {
        let experiment = self
            .experiments
            .get(experiment_name)
            .ok_or_else(|| AppError::NotFound(format!("Experiment: {}", experiment_name)))?;

        // Check if experiment is running
        if experiment.status != ExperimentStatus::Running {
            return Err(AppError::BadRequest(format!(
                "Experiment {} is not running (status: {:?})",
                experiment_name, experiment.status
            )));
        }

        // Consistent hashing
        let mut hasher = DefaultHasher::new();
        user_id.hash(&mut hasher);
        experiment_name.hash(&mut hasher);
        let hash_value = hasher.finish();
        let bucket = (hash_value % 100) as u8;

        // Find variant based on cumulative allocation
        let mut cumulative = 0u8;
        for variant in &experiment.variants {
            cumulative += variant.allocation;
            if bucket < cumulative {
                return Ok(variant.name.clone());
            }
        }

        // Fallback to first variant (should never reach here if allocations sum to 100)
        Ok(experiment.variants[0].name.clone())
    }

    /// Get variant configuration for user
    pub async fn get_variant_config(
        &self,
        user_id: Uuid,
        experiment_name: &str,
    ) -> Result<serde_json::Value> {
        // TODO: Check Redis cache first
        // if let Some(cached) = self.redis_client.get_variant(user_id, experiment_name).await? {
        //     return Ok(cached);
        // }

        // Compute bucket and get variant
        let variant_name = self.assign_bucket(user_id, experiment_name)?;
        let experiment = self.experiments.get(experiment_name).unwrap();
        let variant = experiment
            .variants
            .iter()
            .find(|v| v.name == variant_name)
            .ok_or_else(|| AppError::Internal(format!("Variant {} not found", variant_name)))?;

        // TODO: Cache result in Redis (TTL: 7 days)
        // self.redis_client.set_variant(user_id, experiment_name, &variant.config, 7*24*3600).await?;

        Ok(variant.config.clone())
    }

    /// Log experiment event to ClickHouse
    pub async fn log_event(&self, event: ExperimentEvent) -> Result<()> {
        // TODO: Insert into ClickHouse experiment_events table
        // self.clickhouse_client.insert_experiment_event(event).await?;

        Ok(())
    }

    /// Add or update experiment
    pub fn add_experiment(&mut self, experiment: Experiment) -> Result<()> {
        // Validate allocation sums to 100
        let total_allocation: u8 = experiment.variants.iter().map(|v| v.allocation).sum();
        if total_allocation != 100 {
            return Err(AppError::BadRequest(format!(
                "Variant allocations must sum to 100 (got {})",
                total_allocation
            )));
        }

        self.experiments.insert(experiment.name.clone(), experiment);
        Ok(())
    }

    /// Remove experiment
    pub fn remove_experiment(&mut self, experiment_name: &str) -> Result<()> {
        self.experiments
            .remove(experiment_name)
            .ok_or_else(|| AppError::NotFound(format!("Experiment: {}", experiment_name)))?;
        Ok(())
    }

    /// Get all active experiments
    pub fn get_active_experiments(&self) -> Vec<&Experiment> {
        self.experiments
            .values()
            .filter(|exp| exp.status == ExperimentStatus::Running)
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bucket_assignment_deterministic() {
        let mut framework = ABTestingFramework {
            experiments: HashMap::new(),
        };

        let experiment = Experiment {
            id: 1,
            name: "test_experiment".to_string(),
            description: "Test".to_string(),
            start_date: Utc::now(),
            end_date: None,
            variants: vec![
                Variant {
                    name: "control".to_string(),
                    allocation: 50,
                    config: serde_json::json!({"algorithm": "v1.0"}),
                },
                Variant {
                    name: "variant_a".to_string(),
                    allocation: 50,
                    config: serde_json::json!({"algorithm": "v2.0"}),
                },
            ],
            status: ExperimentStatus::Running,
        };

        framework.add_experiment(experiment).unwrap();

        let user_id = Uuid::new_v4();

        // Same user should always get same variant
        let variant1 = framework.assign_bucket(user_id, "test_experiment").unwrap();
        let variant2 = framework.assign_bucket(user_id, "test_experiment").unwrap();

        assert_eq!(variant1, variant2);
    }

    #[test]
    fn test_allocation_distribution() {
        let mut framework = ABTestingFramework {
            experiments: HashMap::new(),
        };

        let experiment = Experiment {
            id: 1,
            name: "test_experiment".to_string(),
            description: "Test".to_string(),
            start_date: Utc::now(),
            end_date: None,
            variants: vec![
                Variant {
                    name: "control".to_string(),
                    allocation: 50,
                    config: serde_json::json!({"algorithm": "v1.0"}),
                },
                Variant {
                    name: "variant_a".to_string(),
                    allocation: 30,
                    config: serde_json::json!({"algorithm": "v2.0"}),
                },
                Variant {
                    name: "variant_b".to_string(),
                    allocation: 20,
                    config: serde_json::json!({"algorithm": "v2.0"}),
                },
            ],
            status: ExperimentStatus::Running,
        };

        framework.add_experiment(experiment).unwrap();

        // Test with 1000 simulated users
        let mut counts = HashMap::new();
        for _ in 0..1000 {
            let user_id = Uuid::new_v4();
            let variant = framework.assign_bucket(user_id, "test_experiment").unwrap();
            *counts.entry(variant).or_insert(0) += 1;
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

    #[test]
    fn test_invalid_allocation() {
        let mut framework = ABTestingFramework {
            experiments: HashMap::new(),
        };

        let experiment = Experiment {
            id: 1,
            name: "test_experiment".to_string(),
            description: "Test".to_string(),
            start_date: Utc::now(),
            end_date: None,
            variants: vec![Variant {
                name: "control".to_string(),
                allocation: 40, // Only 40%, should fail
                config: serde_json::json!({"algorithm": "v1.0"}),
            }],
            status: ExperimentStatus::Running,
        };

        let result = framework.add_experiment(experiment);
        assert!(result.is_err());
    }
}
