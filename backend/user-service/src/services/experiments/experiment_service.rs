/// Experiment Service - Lifecycle management for A/B tests
use crate::db::experiment_repo::{
    create_experiment, get_experiment, get_experiment_by_name, list_experiments,
    list_experiments_by_status, update_experiment_status, CreateExperimentRequest, Experiment,
    ExperimentStatus,
};
use sqlx::PgPool;
use std::sync::Arc;
use uuid::Uuid;

#[derive(Clone)]
pub struct ExperimentService {
    pool: Arc<PgPool>,
}

impl ExperimentService {
    pub fn new(pool: Arc<PgPool>) -> Self {
        Self { pool }
    }

    /// Create a new experiment with variants
    pub async fn create_experiment(
        &self,
        req: CreateExperimentRequest,
    ) -> Result<Experiment, ExperimentError> {
        // Validate request
        self.validate_create_request(&req)?;

        // Check name uniqueness
        if let Some(_existing) = get_experiment_by_name(&self.pool, &req.name).await? {
            return Err(ExperimentError::DuplicateName(req.name.clone()));
        }

        // Create experiment with variants (transactional)
        let experiment = create_experiment(&self.pool, req).await?;

        Ok(experiment)
    }

    /// Get experiment by ID
    pub async fn get_experiment(&self, id: Uuid) -> Result<Experiment, ExperimentError> {
        get_experiment(&self.pool, id)
            .await?
            .ok_or(ExperimentError::NotFound(id))
    }

    /// Get experiment by name
    pub async fn get_experiment_by_name(&self, name: &str) -> Result<Experiment, ExperimentError> {
        get_experiment_by_name(&self.pool, name)
            .await?
            .ok_or(ExperimentError::NotFoundByName(name.to_string()))
    }

    /// List all experiments
    pub async fn list_experiments(&self) -> Result<Vec<Experiment>, ExperimentError> {
        Ok(list_experiments(&self.pool).await?)
    }

    /// List experiments by status
    pub async fn list_by_status(
        &self,
        status: ExperimentStatus,
    ) -> Result<Vec<Experiment>, ExperimentError> {
        Ok(list_experiments_by_status(&self.pool, status).await?)
    }

    /// Start an experiment (draft -> running)
    pub async fn start_experiment(&self, id: Uuid) -> Result<(), ExperimentError> {
        let experiment = self.get_experiment(id).await?;

        // Validate state transition
        match experiment.status {
            ExperimentStatus::Draft => {
                update_experiment_status(&self.pool, id, ExperimentStatus::Running).await?;
                tracing::info!("Started experiment: {} ({})", experiment.name, id);
                Ok(())
            }
            ExperimentStatus::Running => {
                Err(ExperimentError::InvalidStateTransition {
                    from: "running".to_string(),
                    to: "running".to_string(),
                })
            }
            ExperimentStatus::Completed | ExperimentStatus::Cancelled => {
                Err(ExperimentError::InvalidStateTransition {
                    from: format!("{:?}", experiment.status),
                    to: "running".to_string(),
                })
            }
        }
    }

    /// Stop an experiment (running -> completed)
    pub async fn stop_experiment(&self, id: Uuid) -> Result<(), ExperimentError> {
        let experiment = self.get_experiment(id).await?;

        // Validate state transition
        match experiment.status {
            ExperimentStatus::Running => {
                update_experiment_status(&self.pool, id, ExperimentStatus::Completed).await?;
                tracing::info!("Stopped experiment: {} ({})", experiment.name, id);
                Ok(())
            }
            ExperimentStatus::Draft => Err(ExperimentError::InvalidStateTransition {
                from: "draft".to_string(),
                to: "completed".to_string(),
            }),
            ExperimentStatus::Completed | ExperimentStatus::Cancelled => {
                Err(ExperimentError::InvalidStateTransition {
                    from: format!("{:?}", experiment.status),
                    to: "completed".to_string(),
                })
            }
        }
    }

    /// Cancel an experiment (draft/running -> cancelled)
    pub async fn cancel_experiment(&self, id: Uuid) -> Result<(), ExperimentError> {
        let experiment = self.get_experiment(id).await?;

        match experiment.status {
            ExperimentStatus::Draft | ExperimentStatus::Running => {
                update_experiment_status(&self.pool, id, ExperimentStatus::Cancelled).await?;
                tracing::info!("Cancelled experiment: {} ({})", experiment.name, id);
                Ok(())
            }
            ExperimentStatus::Completed | ExperimentStatus::Cancelled => {
                Err(ExperimentError::InvalidStateTransition {
                    from: format!("{:?}", experiment.status),
                    to: "cancelled".to_string(),
                })
            }
        }
    }

    /// Validate create request
    fn validate_create_request(&self, req: &CreateExperimentRequest) -> Result<(), ExperimentError> {
        // Name validation
        if req.name.trim().is_empty() {
            return Err(ExperimentError::ValidationError(
                "Experiment name cannot be empty".to_string(),
            ));
        }

        // Sample size validation
        if req.sample_size < 0 || req.sample_size > 100 {
            return Err(ExperimentError::ValidationError(
                "Sample size must be between 0 and 100".to_string(),
            ));
        }

        // Variants validation
        if req.variants.is_empty() {
            return Err(ExperimentError::ValidationError(
                "At least one variant is required".to_string(),
            ));
        }

        // Check for duplicate variant names
        let mut names = std::collections::HashSet::new();
        for variant in &req.variants {
            if !names.insert(&variant.name) {
                return Err(ExperimentError::ValidationError(format!(
                    "Duplicate variant name: {}",
                    variant.name
                )));
            }
        }

        // Traffic allocation validation
        let total_allocation: i32 = req.variants.iter().map(|v| v.traffic).sum();
        if total_allocation != 100 {
            return Err(ExperimentError::ValidationError(format!(
                "Total traffic allocation must equal 100%, got {}%",
                total_allocation
            )));
        }

        // Individual traffic validation
        for variant in &req.variants {
            if variant.traffic < 0 || variant.traffic > 100 {
                return Err(ExperimentError::ValidationError(format!(
                    "Variant '{}' traffic must be between 0 and 100",
                    variant.name
                )));
            }
        }

        Ok(())
    }
}

/// Experiment service errors
#[derive(Debug, thiserror::Error)]
pub enum ExperimentError {
    #[error("Experiment not found: {0}")]
    NotFound(Uuid),

    #[error("Experiment not found by name: {0}")]
    NotFoundByName(String),

    #[error("Duplicate experiment name: {0}")]
    DuplicateName(String),

    #[error("Invalid state transition from {from} to {to}")]
    InvalidStateTransition { from: String, to: String },

    #[error("Validation error: {0}")]
    ValidationError(String),

    #[error("Database error: {0}")]
    DatabaseError(#[from] sqlx::Error),
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::experiment_repo::CreateVariantRequest;

    fn mock_create_request() -> CreateExperimentRequest {
        CreateExperimentRequest {
            name: "test_experiment".to_string(),
            description: Some("Test description".to_string()),
            stratification_key: "user_id".to_string(),
            sample_size: 50,
            variants: vec![
                CreateVariantRequest {
                    name: "control".to_string(),
                    config: serde_json::json!({"feature_enabled": false}),
                    traffic: 50,
                },
                CreateVariantRequest {
                    name: "treatment".to_string(),
                    config: serde_json::json!({"feature_enabled": true}),
                    traffic: 50,
                },
            ],
            created_by: None,
        }
    }

    #[test]
    fn test_validate_request_success() {
        let service = ExperimentService {
            pool: Arc::new(PgPool::connect_lazy("").unwrap()),
        };
        let req = mock_create_request();
        assert!(service.validate_create_request(&req).is_ok());
    }

    #[test]
    fn test_validate_request_empty_name() {
        let service = ExperimentService {
            pool: Arc::new(PgPool::connect_lazy("").unwrap()),
        };
        let mut req = mock_create_request();
        req.name = "".to_string();
        assert!(matches!(
            service.validate_create_request(&req),
            Err(ExperimentError::ValidationError(_))
        ));
    }

    #[test]
    fn test_validate_request_invalid_sample_size() {
        let service = ExperimentService {
            pool: Arc::new(PgPool::connect_lazy("").unwrap()),
        };
        let mut req = mock_create_request();
        req.sample_size = 150;
        assert!(matches!(
            service.validate_create_request(&req),
            Err(ExperimentError::ValidationError(_))
        ));
    }

    #[test]
    fn test_validate_request_invalid_traffic_allocation() {
        let service = ExperimentService {
            pool: Arc::new(PgPool::connect_lazy("").unwrap()),
        };
        let mut req = mock_create_request();
        req.variants[0].traffic = 60;
        assert!(matches!(
            service.validate_create_request(&req),
            Err(ExperimentError::ValidationError(_))
        ));
    }

    #[test]
    fn test_validate_request_duplicate_variant_names() {
        let service = ExperimentService {
            pool: Arc::new(PgPool::connect_lazy("").unwrap()),
        };
        let mut req = mock_create_request();
        req.variants[1].name = "control".to_string();
        assert!(matches!(
            service.validate_create_request(&req),
            Err(ExperimentError::ValidationError(_))
        ));
    }
}
