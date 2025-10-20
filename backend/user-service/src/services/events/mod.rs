/// Events consumer service
///
/// Consumes application events from Kafka and stores them in ClickHouse for
/// analytics and behavior tracking.
///
/// # Architecture
/// - **Deduplicator**: Redis-backed deduplication (prevents duplicate processing)
/// - **Consumer**: Kafka consumer with batch processing
///
/// # Guarantees
/// - Exactly-once processing (via Redis deduplication)
/// - Batch inserts for efficiency (100 events per batch)
/// - Automatic offset management (auto-commit enabled)
pub mod consumer;
pub mod dedup;

pub use consumer::{EventMessage, EventsConsumer, EventsConsumerConfig};
pub use dedup::EventDeduplicator;
