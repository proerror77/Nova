//! Kafka consumer for notification events with batch aggregation

use crate::services::notifications::models::{
    NotificationEvent, NotificationBatch,
};
use serde_json;
use tracing::info;
use std::sync::Arc;
use tokio::sync::RwLock;

/// Configuration for notification consumer
#[derive(Debug, Clone)]
pub struct ConsumerConfig {
    /// Kafka brokers (comma-separated)
    pub brokers: String,
    /// Consumer group ID
    pub group_id: String,
    /// Topic to consume
    pub topic: String,
    /// Batch size before flush
    pub batch_size: usize,
    /// Batch timeout in seconds
    pub batch_timeout_secs: i64,
}

impl Default for ConsumerConfig {
    fn default() -> Self {
        Self {
            brokers: "localhost:9092".to_string(),
            group_id: "nova-notifications".to_string(),
            topic: "nova-notifications".to_string(),
            batch_size: 100,
            batch_timeout_secs: 1,
        }
    }
}

/// Kafka consumer for notifications
pub struct NotificationConsumer {
    config: ConsumerConfig,
    batch: Arc<RwLock<NotificationBatch>>,
    stats: Arc<RwLock<ConsumerStats>>,
}

/// Consumer statistics
#[derive(Debug, Clone, Default)]
pub struct ConsumerStats {
    pub total_events: u64,
    pub total_batches: u64,
    pub failed_events: u64,
    pub last_batch_size: usize,
    pub last_batch_time_ms: u64,
}

impl NotificationConsumer {
    /// Create a new consumer
    pub fn new(config: ConsumerConfig) -> Self {
        info!(
            "Creating notification consumer: topic={}, batch_size={}",
            config.topic, config.batch_size
        );

        Self {
            config,
            batch: Arc::new(RwLock::new(NotificationBatch::new())),
            stats: Arc::new(RwLock::new(ConsumerStats::default())),
        }
    }

    /// Process incoming event
    pub async fn process_event(&self, payload: &str) -> Result<Option<Vec<NotificationEvent>>, String> {
        // Parse JSON event
        let event: NotificationEvent = serde_json::from_str(payload)
            .map_err(|e| format!("Failed to parse event: {}", e))?;

        // Add to batch
        let mut batch = self.batch.write().await;
        batch.push(event.clone());

        // Update stats
        let mut stats = self.stats.write().await;
        stats.total_events += 1;

        // Check if batch should flush
        if batch.should_flush(self.config.batch_size, self.config.batch_timeout_secs) {
            let events = batch.events.clone();
            let batch_size = batch.count;

            batch.clear();
            drop(batch); // Release lock before updating stats

            // Update stats
            stats.total_batches += 1;
            stats.last_batch_size = batch_size;

            info!("Flushing batch: size={}, total_events={}", batch_size, stats.total_events);
            Ok(Some(events))
        } else {
            Ok(None)
        }
    }

    /// Get current batch size
    pub async fn batch_size(&self) -> usize {
        self.batch.read().await.count
    }

    /// Get statistics
    pub async fn stats(&self) -> ConsumerStats {
        self.stats.read().await.clone()
    }

    /// Reset statistics
    pub async fn reset_stats(&self) {
        let mut stats = self.stats.write().await;
        stats.total_events = 0;
        stats.total_batches = 0;
        stats.failed_events = 0;
    }

    /// Force flush current batch
    pub async fn flush(&self) -> Option<Vec<NotificationEvent>> {
        let mut batch = self.batch.write().await;
        if batch.count == 0 {
            return None;
        }

        let events = batch.events.clone();
        batch.clear();

        let mut stats = self.stats.write().await;
        stats.total_batches += 1;
        stats.last_batch_size = events.len();

        Some(events)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;
    use std::collections::HashMap;

    #[tokio::test]
    async fn test_consumer_creation() {
        let config = ConsumerConfig::default();
        let consumer = NotificationConsumer::new(config);
        assert_eq!(consumer.batch_size().await, 0);
    }

    #[tokio::test]
    async fn test_process_event() {
        let config = ConsumerConfig {
            batch_size: 10,
            ..Default::default()
        };
        let consumer = NotificationConsumer::new(config);

        let event = NotificationEvent {
            id: "test-1".to_string(),
            event_type: NotificationType::Like,
            recipient_id: Uuid::new_v4(),
            actor_id: Some(Uuid::new_v4()),
            related_entity_id: Some("post-1".to_string()),
            timestamp: Utc::now().timestamp(),
            metadata: HashMap::new(),
        };

        let payload = serde_json::to_string(&event).unwrap();
        let result = consumer.process_event(&payload).await;

        assert!(result.is_ok());
        assert_eq!(consumer.batch_size().await, 1);
    }

    #[tokio::test]
    async fn test_batch_flush_on_size() {
        let config = ConsumerConfig {
            batch_size: 3,
            ..Default::default()
        };
        let consumer = NotificationConsumer::new(config);

        for i in 0..3 {
            let event = NotificationEvent {
                id: format!("test-{}", i),
                event_type: NotificationType::Comment,
                recipient_id: Uuid::new_v4(),
                actor_id: None,
                related_entity_id: None,
                timestamp: Utc::now().timestamp(),
                metadata: HashMap::new(),
            };

            let payload = serde_json::to_string(&event).unwrap();
            let result = consumer.process_event(&payload).await.unwrap();

            if i < 2 {
                assert!(result.is_none());
            } else {
                assert!(result.is_some());
                let flushed = result.unwrap();
                assert_eq!(flushed.len(), 3);
            }
        }
    }

    #[tokio::test]
    async fn test_force_flush() {
        let config = ConsumerConfig::default();
        let consumer = NotificationConsumer::new(config);

        let event = NotificationEvent {
            id: "test-1".to_string(),
            event_type: NotificationType::Follow,
            recipient_id: Uuid::new_v4(),
            actor_id: None,
            related_entity_id: None,
            timestamp: Utc::now().timestamp(),
            metadata: HashMap::new(),
        };

        let payload = serde_json::to_string(&event).unwrap();
        let _ = consumer.process_event(&payload).await;

        assert_eq!(consumer.batch_size().await, 1);

        let flushed = consumer.flush().await;
        assert!(flushed.is_some());
        assert_eq!(flushed.unwrap().len(), 1);
        assert_eq!(consumer.batch_size().await, 0);
    }

    #[tokio::test]
    async fn test_consumer_stats() {
        let config = ConsumerConfig::default();
        let consumer = NotificationConsumer::new(config);

        let event = NotificationEvent {
            id: "test-1".to_string(),
            event_type: NotificationType::LiveStart,
            recipient_id: Uuid::new_v4(),
            actor_id: None,
            related_entity_id: None,
            timestamp: Utc::now().timestamp(),
            metadata: HashMap::new(),
        };

        let payload = serde_json::to_string(&event).unwrap();
        let _ = consumer.process_event(&payload).await;

        let stats = consumer.stats().await;
        assert_eq!(stats.total_events, 1);

        consumer.reset_stats().await;
        let stats = consumer.stats().await;
        assert_eq!(stats.total_events, 0);
    }
}
