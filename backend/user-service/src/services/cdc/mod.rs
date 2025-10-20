/// CDC (Change Data Capture) consumer service
///
/// Consumes Debezium CDC messages from Kafka and synchronizes them to ClickHouse.
///
/// # Architecture
/// - **Models**: CDC message structures (Debezium format)
/// - **Offset Manager**: Persistent offset storage in PostgreSQL
/// - **Consumer**: Kafka consumer with exactly-once semantics
///
/// # Guarantees
/// - At-least-once delivery (via manual offset commit after CH insert)
/// - Offset persistence across restarts (PostgreSQL-backed)
/// - Idempotent inserts (ClickHouse ReplacingMergeTree)
pub mod consumer;
pub mod models;
pub mod offset_manager;

pub use consumer::{CdcConsumer, CdcConsumerConfig};
pub use models::{CdcMessage, CdcOperation};
pub use offset_manager::OffsetManager;
