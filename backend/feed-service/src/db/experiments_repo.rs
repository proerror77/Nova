//! Experiments Repository
//!
//! Database operations for the A/B testing framework with user validation.
//! Implements CRUD for experiments, variants, assignments, and metrics.
//! All user_id references are validated via AuthClient before INSERT.

use crate::error::{AppError, Result};
use grpc_clients::AuthClient;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use std::sync::Arc;
use tracing::{error, info};
use uuid::Uuid;

/// Experiment status (matches database enum)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "experiment_status", rename_all = "lowercase")]
#[serde(rename_all = "lowercase")]
pub enum ExperimentStatus {
    Draft,
    Running,
    Completed,
    Cancelled,
}

/// Experiment from database
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Experiment {
    pub id: Uuid,
    pub name: String,
    pub description: Option<String>,
    pub status: ExperimentStatus,
    pub start_date: Option<DateTime<Utc>>,
    pub end_date: Option<DateTime<Utc>>,
    pub stratification_key: String,
    pub sample_size: i32,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub created_by: Option<Uuid>,
}

/// Experiment variant from database
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct ExperimentVariant {
    pub id: Uuid,
    pub experiment_id: Uuid,
    pub variant_name: String,
    pub variant_config: serde_json::Value,
    pub traffic_allocation: i32,
    pub created_at: DateTime<Utc>,
}

/// User variant assignment from database
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct ExperimentAssignment {
    pub id: Uuid,
    pub experiment_id: Uuid,
    pub user_id: Uuid,
    pub variant_id: Uuid,
    pub assigned_at: DateTime<Utc>,
}

/// Experiment metric event from database
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct ExperimentMetric {
    pub id: Uuid,
    pub experiment_id: Uuid,
    pub user_id: Uuid,
    pub variant_id: Option<Uuid>,
    pub metric_name: String,
    pub metric_value: f64, // NUMERIC -> f64
    pub recorded_at: DateTime<Utc>,
}

/// Experiments Repository with AuthService validation
pub struct ExperimentsRepo {
    pool: PgPool,
    auth_client: Arc<AuthClient>,
}

impl ExperimentsRepo {
    pub fn new(pool: PgPool, auth_client: Arc<AuthClient>) -> Self {
        Self { pool, auth_client }
    }

    /// Create a new experiment
    ///
    /// # Validation
    /// - Validates `created_by` user exists via AuthClient
    ///
    /// # Errors
    /// Returns error if:
    /// - created_by user doesn't exist
    /// - experiment name already exists (UNIQUE constraint)
    /// - date range is invalid
    pub async fn create_experiment(
        &self,
        name: String,
        description: Option<String>,
        created_by: Uuid,
        start_date: Option<DateTime<Utc>>,
        end_date: Option<DateTime<Utc>>,
        stratification_key: Option<String>,
        sample_size: i32,
    ) -> Result<Experiment> {
        // ✅ VALIDATION POINT 1: Verify created_by user exists
        self.auth_client.validate_user_exists(created_by).await?;

        let experiment = sqlx::query_as::<_, Experiment>(
            r#"
            INSERT INTO experiments (
                name,
                description,
                created_by,
                start_date,
                end_date,
                stratification_key,
                sample_size,
                status
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, 'draft')
            RETURNING id, name, description, status, start_date, end_date,
                      stratification_key, sample_size, created_at, updated_at, created_by
            "#,
        )
        .bind(&name)
        .bind(&description)
        .bind(created_by)
        .bind(start_date)
        .bind(end_date)
        .bind(stratification_key.unwrap_or_else(|| "user_id".to_string()))
        .bind(sample_size)
        .fetch_one(&self.pool)
        .await
        .map_err(|e| {
            error!("Failed to create experiment '{}': {}", name, e);
            AppError::Database(e.to_string())
        })?;

        info!(
            "Created experiment '{}' (id={}, created_by={})",
            experiment.name, experiment.id, created_by
        );

        Ok(experiment)
    }

    /// Create a variant assignment for a user
    ///
    /// # Validation
    /// - Validates `user_id` exists via AuthClient
    ///
    /// # Errors
    /// Returns error if:
    /// - user_id doesn't exist
    /// - user already assigned to this experiment (UNIQUE constraint)
    /// - experiment_id or variant_id doesn't exist (FK constraint)
    pub async fn create_assignment(
        &self,
        experiment_id: Uuid,
        user_id: Uuid,
        variant_id: Uuid,
    ) -> Result<ExperimentAssignment> {
        // ✅ VALIDATION POINT 2: Verify user_id exists
        self.auth_client.validate_user_exists(user_id).await?;

        let assignment = sqlx::query_as::<_, ExperimentAssignment>(
            r#"
            INSERT INTO experiment_assignments (experiment_id, user_id, variant_id)
            VALUES ($1, $2, $3)
            RETURNING id, experiment_id, user_id, variant_id, assigned_at
            "#,
        )
        .bind(experiment_id)
        .bind(user_id)
        .bind(variant_id)
        .fetch_one(&self.pool)
        .await
        .map_err(|e| {
            error!(
                "Failed to create assignment (experiment={}, user={}, variant={}): {}",
                experiment_id, user_id, variant_id, e
            );
            AppError::Database(e.to_string())
        })?;

        info!(
            "Assigned user {} to variant {} in experiment {}",
            user_id, variant_id, experiment_id
        );

        Ok(assignment)
    }

    /// Record a metric event for a user
    ///
    /// # Validation
    /// - Validates `user_id` exists via AuthClient
    ///
    /// # Errors
    /// Returns error if:
    /// - user_id doesn't exist
    /// - experiment_id or variant_id doesn't exist (FK constraint)
    pub async fn record_metric(
        &self,
        experiment_id: Uuid,
        user_id: Uuid,
        variant_id: Option<Uuid>,
        metric_name: String,
        metric_value: f64,
    ) -> Result<ExperimentMetric> {
        // ✅ VALIDATION POINT 3: Verify user_id exists
        self.auth_client.validate_user_exists(user_id).await?;

        let metric = sqlx::query_as::<_, ExperimentMetric>(
            r#"
            INSERT INTO experiment_metrics (
                experiment_id,
                user_id,
                variant_id,
                metric_name,
                metric_value
            )
            VALUES ($1, $2, $3, $4, $5)
            RETURNING id, experiment_id, user_id, variant_id, metric_name,
                      metric_value, recorded_at
            "#,
        )
        .bind(experiment_id)
        .bind(user_id)
        .bind(variant_id)
        .bind(&metric_name)
        .bind(metric_value)
        .fetch_one(&self.pool)
        .await
        .map_err(|e| {
            error!(
                "Failed to record metric '{}' for user {} in experiment {}: {}",
                metric_name, user_id, experiment_id, e
            );
            AppError::Database(e.to_string())
        })?;

        info!(
            "Recorded metric '{}' = {} for user {} in experiment {}",
            metric_name, metric_value, user_id, experiment_id
        );

        Ok(metric)
    }

    /// Get experiment by ID
    pub async fn get_experiment(&self, id: Uuid) -> Result<Option<Experiment>> {
        let experiment = sqlx::query_as::<_, Experiment>(
            r#"
            SELECT id, name, description, status, start_date, end_date,
                   stratification_key, sample_size, created_at, updated_at, created_by
            FROM experiments
            WHERE id = $1
            "#,
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| {
            error!("Failed to get experiment {}: {}", id, e);
            AppError::Database(e.to_string())
        })?;

        Ok(experiment)
    }

    /// List experiments with optional status filter
    pub async fn list_experiments(
        &self,
        status: Option<ExperimentStatus>,
    ) -> Result<Vec<Experiment>> {
        let experiments = if let Some(status_filter) = status {
            sqlx::query_as::<_, Experiment>(
                r#"
                SELECT id, name, description, status, start_date, end_date,
                       stratification_key, sample_size, created_at, updated_at, created_by
                FROM experiments
                WHERE status = $1
                ORDER BY created_at DESC
                "#,
            )
            .bind(status_filter)
            .fetch_all(&self.pool)
            .await
        } else {
            sqlx::query_as::<_, Experiment>(
                r#"
                SELECT id, name, description, status, start_date, end_date,
                       stratification_key, sample_size, created_at, updated_at, created_by
                FROM experiments
                ORDER BY created_at DESC
                "#,
            )
            .fetch_all(&self.pool)
            .await
        }
        .map_err(|e| {
            error!("Failed to list experiments: {}", e);
            AppError::Database(e.to_string())
        })?;

        Ok(experiments)
    }

    /// Get user's assigned variant for an experiment
    pub async fn get_user_variant(
        &self,
        experiment_id: Uuid,
        user_id: Uuid,
    ) -> Result<Option<Uuid>> {
        let variant_id = sqlx::query_scalar::<_, Uuid>(
            r#"
            SELECT variant_id
            FROM experiment_assignments
            WHERE experiment_id = $1 AND user_id = $2
            "#,
        )
        .bind(experiment_id)
        .bind(user_id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| {
            error!(
                "Failed to get user variant (experiment={}, user={}): {}",
                experiment_id, user_id, e
            );
            AppError::Database(e.to_string())
        })?;

        Ok(variant_id)
    }

    /// Create a variant for an experiment
    pub async fn create_variant(
        &self,
        experiment_id: Uuid,
        variant_name: String,
        variant_config: serde_json::Value,
        traffic_allocation: i32,
    ) -> Result<ExperimentVariant> {
        let variant = sqlx::query_as::<_, ExperimentVariant>(
            r#"
            INSERT INTO experiment_variants (
                experiment_id,
                variant_name,
                variant_config,
                traffic_allocation
            )
            VALUES ($1, $2, $3, $4)
            RETURNING id, experiment_id, variant_name, variant_config,
                      traffic_allocation, created_at
            "#,
        )
        .bind(experiment_id)
        .bind(&variant_name)
        .bind(&variant_config)
        .bind(traffic_allocation)
        .fetch_one(&self.pool)
        .await
        .map_err(|e| {
            error!(
                "Failed to create variant '{}' for experiment {}: {}",
                variant_name, experiment_id, e
            );
            AppError::Database(e.to_string())
        })?;

        info!(
            "Created variant '{}' (id={}) for experiment {}",
            variant_name, variant.id, experiment_id
        );

        Ok(variant)
    }

    /// Get all variants for an experiment
    pub async fn get_variants(&self, experiment_id: Uuid) -> Result<Vec<ExperimentVariant>> {
        let variants = sqlx::query_as::<_, ExperimentVariant>(
            r#"
            SELECT id, experiment_id, variant_name, variant_config,
                   traffic_allocation, created_at
            FROM experiment_variants
            WHERE experiment_id = $1
            ORDER BY created_at ASC
            "#,
        )
        .bind(experiment_id)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| {
            error!("Failed to get variants for experiment {}: {}", experiment_id, e);
            AppError::Database(e.to_string())
        })?;

        Ok(variants)
    }

    /// Update experiment status
    pub async fn update_status(
        &self,
        experiment_id: Uuid,
        status: ExperimentStatus,
    ) -> Result<Experiment> {
        let experiment = sqlx::query_as::<_, Experiment>(
            r#"
            UPDATE experiments
            SET status = $1, updated_at = NOW()
            WHERE id = $2
            RETURNING id, name, description, status, start_date, end_date,
                      stratification_key, sample_size, created_at, updated_at, created_by
            "#,
        )
        .bind(status)
        .bind(experiment_id)
        .fetch_one(&self.pool)
        .await
        .map_err(|e| {
            error!("Failed to update experiment {} status: {}", experiment_id, e);
            AppError::Database(e.to_string())
        })?;

        info!("Updated experiment {} status to {:?}", experiment_id, status);

        Ok(experiment)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_experiment_status_serde() {
        let status = ExperimentStatus::Running;
        let json = serde_json::to_string(&status).unwrap();
        assert_eq!(json, "\"running\"");

        let parsed: ExperimentStatus = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed, ExperimentStatus::Running);
    }

    #[test]
    fn test_experiment_status_variants() {
        let statuses = vec![
            ExperimentStatus::Draft,
            ExperimentStatus::Running,
            ExperimentStatus::Completed,
            ExperimentStatus::Cancelled,
        ];

        for status in statuses {
            let json = serde_json::to_string(&status).unwrap();
            let parsed: ExperimentStatus = serde_json::from_str(&json).unwrap();
            assert_eq!(parsed, status);
        }
    }
}
