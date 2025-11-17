/// Kafka utilities and patterns
///
/// This module provides common Kafka patterns for reliable message processing:
/// - **Deduplication**: Prevent duplicate message processing (CDC events)
/// - **Retries**: Handle transient failures
/// - **Monitoring**: Track Kafka operations
pub mod deduplicator;

pub use deduplicator::KafkaDeduplicator;
