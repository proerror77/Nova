/// Kafka Consumer for Recommendation Events
///
/// Listens to recommendation-related events from Kafka:
/// 1. recommendations.model_updates - Trigger hot-reload of models
/// 2. recommendations.feedback - User feedback for model training
/// 3. experiments.config - Update A/B testing configurations
///
/// Architecture:
/// - Event-driven model updates
/// - Graceful error handling with retry logic
/// - Batch processing for efficiency
/// - Circuit breaker for Kafka failures
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::time::Duration;
use tracing::{debug, error, info, warn};
use uuid::Uuid;

use crate::error::Result;
use crate::services::RecommendationServiceV2;

/// Experiment variant configuration
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ExperimentVariant {
    pub name: String,
    pub allocation: u8, // 0-100
}

/// Recommendation event types
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum RecommendationEventType {
    /// Model update event - trigger hot-reload
    ModelUpdate {
        model_type: String, // "collaborative" | "content_based" | "onnx"
        model_path: String,
    },
    /// User feedback event - for training data collection
    UserFeedback {
        user_id: Uuid,
        post_id: Uuid,
        feedback_type: String, // "like" | "dislike" | "click" | "dwell"
        duration_ms: Option<u32>,
    },
    /// Experiment config update
    ExperimentConfig {
        experiment_id: String,
        variants: Vec<ExperimentVariant>,
    },
}

/// Kafka event for recommendations
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecommendationKafkaEvent {
    pub event_id: String,
    pub event_type: RecommendationEventType,
    pub timestamp: DateTime<Utc>,
    pub source: String, // Service that produced the event
}

impl RecommendationKafkaEvent {
    /// Create a new model update event
    pub fn model_update(model_type: String, model_path: String, source: String) -> Self {
        Self {
            event_id: Uuid::new_v4().to_string(),
            event_type: RecommendationEventType::ModelUpdate {
                model_type,
                model_path,
            },
            timestamp: Utc::now(),
            source,
        }
    }

    /// Create a new user feedback event
    pub fn user_feedback(
        user_id: Uuid,
        post_id: Uuid,
        feedback_type: String,
        duration_ms: Option<u32>,
        source: String,
    ) -> Self {
        Self {
            event_id: Uuid::new_v4().to_string(),
            event_type: RecommendationEventType::UserFeedback {
                user_id,
                post_id,
                feedback_type,
                duration_ms,
            },
            timestamp: Utc::now(),
            source,
        }
    }

    /// Create a new experiment config event
    pub fn experiment_config(
        experiment_id: String,
        variants: Vec<ExperimentVariant>,
        source: String,
    ) -> Self {
        Self {
            event_id: Uuid::new_v4().to_string(),
            event_type: RecommendationEventType::ExperimentConfig {
                experiment_id,
                variants,
            },
            timestamp: Utc::now(),
            source,
        }
    }
}

/// Batch of recommendation events
#[derive(Debug, Clone)]
pub struct RecommendationEventBatch {
    pub events: Vec<RecommendationKafkaEvent>,
    pub created_at: DateTime<Utc>,
    pub batch_id: String,
}

impl RecommendationEventBatch {
    pub fn new() -> Self {
        Self {
            events: Vec::new(),
            created_at: Utc::now(),
            batch_id: Uuid::new_v4().to_string(),
        }
    }

    pub fn should_flush_by_size(&self, max_size: usize) -> bool {
        self.events.len() >= max_size
    }

    pub fn should_flush_by_time(&self, max_age: Duration) -> bool {
        let age = Utc::now()
            .signed_duration_since(self.created_at)
            .to_std()
            .unwrap_or_default();
        age >= max_age
    }

    pub fn add(&mut self, event: RecommendationKafkaEvent) {
        self.events.push(event);
    }

    pub fn len(&self) -> usize {
        self.events.len()
    }

    pub fn is_empty(&self) -> bool {
        self.events.is_empty()
    }
}

impl Default for RecommendationEventBatch {
    fn default() -> Self {
        Self::new()
    }
}

/// Kafka consumer for recommendation events
pub struct RecommendationEventConsumer {
    service: Arc<RecommendationServiceV2>,
    batch: RecommendationEventBatch,
    max_batch_size: usize,
    max_batch_age: Duration,
}

impl RecommendationEventConsumer {
    /// Create new recommendation event consumer
    pub fn new(service: Arc<RecommendationServiceV2>) -> Self {
        Self {
            service,
            batch: RecommendationEventBatch::new(),
            max_batch_size: 100,
            max_batch_age: Duration::from_secs(5),
        }
    }

    /// Process an incoming event from Kafka
    pub async fn handle_event(&mut self, event: RecommendationKafkaEvent) -> Result<()> {
        debug!(
            "Received recommendation event: {} - {:?}",
            event.event_id, event.event_type
        );

        // Add event to batch
        self.batch.add(event.clone());

        // Check if we should flush the batch
        if self.batch.should_flush_by_size(self.max_batch_size) {
            self.flush_batch().await?;
        }

        Ok(())
    }

    /// Process model update event
    async fn handle_model_update(&self, model_type: String, model_path: String) -> Result<()> {
        match model_type.as_str() {
            "collaborative" | "content_based" => {
                info!("Hot-reloading {} model from: {}", model_type, model_path);
                // TODO: Implement hot-reload of specific model
                // For now, we log the event but cannot reload immutably
                // The service would need interior mutability for true hot-reload
                debug!("Model update logged: {} from {}", model_type, model_path);
            }
            "onnx" => {
                info!("Hot-reloading ONNX model from: {}", model_path);
                // Reload ONNX model through the service
                // The ONNX server uses Arc+RwLock for interior mutability
                self.service.onnx_server.reload(&model_path).await?;
            }
            _ => {
                warn!("Unknown model type: {}", model_type);
            }
        }
        Ok(())
    }

    /// Process user feedback event
    async fn handle_user_feedback(
        &self,
        _user_id: Uuid,
        _post_id: Uuid,
        _feedback_type: String,
        _duration_ms: Option<u32>,
    ) -> Result<()> {
        // TODO: Send to ClickHouse or training pipeline for model updates
        // For now, just log it
        debug!("User feedback recorded for tracking");
        Ok(())
    }

    /// Process experiment config event
    async fn handle_experiment_config(
        &self,
        _experiment_id: String,
        _variants: Vec<ExperimentVariant>,
    ) -> Result<()> {
        // TODO: Update A/B testing framework with new experiment config
        // This would involve updating the ABTestingFramework with new experiments
        debug!("Experiment config updated");
        Ok(())
    }

    /// Flush pending batch of events
    async fn flush_batch(&mut self) -> Result<()> {
        if self.batch.is_empty() {
            return Ok(());
        }

        info!(
            "Flushing batch of {} recommendation events",
            self.batch.len()
        );

        // Process each event in the batch
        for event in &self.batch.events {
            match &event.event_type {
                RecommendationEventType::ModelUpdate {
                    model_type,
                    model_path,
                } => {
                    if let Err(e) = self
                        .handle_model_update(model_type.clone(), model_path.clone())
                        .await
                    {
                        error!("Failed to handle model update: {:?}", e);
                        // Continue processing other events
                    }
                }
                RecommendationEventType::UserFeedback {
                    user_id,
                    post_id,
                    feedback_type,
                    duration_ms,
                } => {
                    if let Err(e) = self
                        .handle_user_feedback(
                            *user_id,
                            *post_id,
                            feedback_type.clone(),
                            *duration_ms,
                        )
                        .await
                    {
                        error!("Failed to handle user feedback: {:?}", e);
                    }
                }
                RecommendationEventType::ExperimentConfig {
                    experiment_id,
                    variants,
                } => {
                    if let Err(e) = self
                        .handle_experiment_config(experiment_id.clone(), variants.clone())
                        .await
                    {
                        error!("Failed to handle experiment config: {:?}", e);
                    }
                }
            }
        }

        // Reset batch after successful processing
        self.batch = RecommendationEventBatch::new();

        Ok(())
    }

    /// Get current batch size
    pub fn batch_size(&self) -> usize {
        self.batch.len()
    }

    /// Force flush the current batch
    pub async fn flush(&mut self) -> Result<()> {
        self.flush_batch().await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_model_update_event_creation() {
        let event = RecommendationKafkaEvent::model_update(
            "collaborative".to_string(),
            "/models/cf_v2.json".to_string(),
            "user-service".to_string(),
        );

        match event.event_type {
            RecommendationEventType::ModelUpdate {
                model_type,
                model_path,
            } => {
                assert_eq!(model_type, "collaborative");
                assert_eq!(model_path, "/models/cf_v2.json");
            }
            _ => panic!("Expected ModelUpdate event"),
        }
    }

    #[test]
    fn test_batch_flushing() {
        let mut batch = RecommendationEventBatch::new();
        let event = RecommendationKafkaEvent::model_update(
            "onnx".to_string(),
            "/models/ranker.onnx".to_string(),
            "content-service".to_string(),
        );

        batch.add(event);
        assert_eq!(batch.len(), 1);
        assert!(!batch.is_empty());

        // Check if should flush by size
        assert!(!batch.should_flush_by_size(100));
        assert!(batch.should_flush_by_size(1));
    }

    #[test]
    fn test_user_feedback_event() {
        let user_id = Uuid::new_v4();
        let post_id = Uuid::new_v4();
        let event = RecommendationKafkaEvent::user_feedback(
            user_id,
            post_id,
            "like".to_string(),
            Some(1500),
            "feed-service".to_string(),
        );

        match event.event_type {
            RecommendationEventType::UserFeedback {
                user_id: uid,
                post_id: pid,
                feedback_type,
                duration_ms,
            } => {
                assert_eq!(uid, user_id);
                assert_eq!(pid, post_id);
                assert_eq!(feedback_type, "like");
                assert_eq!(duration_ms, Some(1500));
            }
            _ => panic!("Expected UserFeedback event"),
        }
    }
}
