/// WebSocket and messaging metrics
use lazy_static::lazy_static;
use prometheus::{
    register_counter, register_counter_vec, register_gauge, register_gauge_vec,
    register_histogram, register_histogram_vec, Counter, CounterVec, Gauge, GaugeVec,
    Histogram, HistogramVec,
};

lazy_static! {
    // ======================
    // WebSocket Counters
    // ======================

    /// Total WebSocket connections (labels: status=opened|closed|error)
    pub static ref WS_CONNECTIONS_TOTAL: CounterVec = register_counter_vec!(
        "ws_connections_total",
        "Total number of WebSocket connections",
        &["status"]
    )
    .unwrap();

    /// Total WebSocket message sends (labels: type=message|typing|ping|pong)
    pub static ref WS_MESSAGES_SENT_TOTAL: CounterVec = register_counter_vec!(
        "ws_messages_sent_total",
        "Total WebSocket messages sent",
        &["message_type"]
    )
    .unwrap();

    /// Total WebSocket message receives (labels: type=message|typing|ping|pong)
    pub static ref WS_MESSAGES_RECEIVED_TOTAL: CounterVec = register_counter_vec!(
        "ws_messages_received_total",
        "Total WebSocket messages received",
        &["message_type"]
    )
    .unwrap();

    /// WebSocket errors (labels: error_type=timeout|decode|send_failed|connection_lost)
    pub static ref WS_ERRORS_TOTAL: CounterVec = register_counter_vec!(
        "ws_errors_total",
        "Total WebSocket errors",
        &["error_type"]
    )
    .unwrap();

    /// WebSocket reconnections (labels: reason=connection_lost|heartbeat_timeout)
    pub static ref WS_RECONNECTIONS_TOTAL: CounterVec = register_counter_vec!(
        "ws_reconnections_total",
        "Total WebSocket reconnection attempts",
        &["reason"]
    )
    .unwrap();

    // ======================
    // Messaging API Counters
    // ======================

    /// Total messages sent (labels: status=success|failed)
    pub static ref MESSAGES_SENT_TOTAL: CounterVec = register_counter_vec!(
        "messages_sent_total",
        "Total messages sent",
        &["status"]
    )
    .unwrap();

    /// Total messages received (labels: status=success|failed)
    pub static ref MESSAGES_RECEIVED_TOTAL: CounterVec = register_counter_vec!(
        "messages_received_total",
        "Total messages received",
        &["status"]
    )
    .unwrap();

    /// Message delivery failures (labels: error_type=network|timeout|invalid|other)
    pub static ref MESSAGE_DELIVERY_FAILURES_TOTAL: CounterVec = register_counter_vec!(
        "message_delivery_failures_total",
        "Total message delivery failures",
        &["error_type"]
    )
    .unwrap();

    /// Total conversation creations (labels: status=success|failed)
    pub static ref CONVERSATIONS_CREATED_TOTAL: CounterVec = register_counter_vec!(
        "conversations_created_total",
        "Total conversations created",
        &["status"]
    )
    .unwrap();

    /// Total message searches (labels: index=fulltext|bm25, status=success|failed)
    pub static ref MESSAGE_SEARCHES_TOTAL: CounterVec = register_counter_vec!(
        "message_searches_total",
        "Total message searches",
        &["index_type", "status"]
    )
    .unwrap();

    // ======================
    // WebSocket Gauges
    // ======================

    /// Current active WebSocket connections (no labels - bounded metric)
    /// NOTE: We intentionally do NOT use conversation_id as label
    /// because it would create unbounded cardinality (1 series per conversation).
    /// Per-conversation breakdown is not needed for alerting; total is sufficient.
    pub static ref WS_ACTIVE_CONNECTIONS: Gauge = register_gauge!(
        "ws_active_connections",
        "Current active WebSocket connections (total across all conversations)"
    )
    .unwrap();

    /// Current active conversations
    pub static ref ACTIVE_CONVERSATIONS: GaugeVec = register_gauge_vec!(
        "active_conversations",
        "Current active conversations",
        &["status"]  // status=idle|active
    )
    .unwrap();

    /// Message queue depth (labels: queue_type=pending|failed|retry)
    pub static ref MESSAGE_QUEUE_DEPTH: GaugeVec = register_gauge_vec!(
        "message_queue_depth",
        "Current message queue depth",
        &["queue_type"]
    )
    .unwrap();

    // ======================
    // Latency Histograms
    // ======================

    /// WebSocket message latency in seconds (labels: message_type=message|typing)
    pub static ref WS_MESSAGE_LATENCY_SECONDS: HistogramVec = register_histogram_vec!(
        "ws_message_latency_seconds",
        "WebSocket message latency in seconds",
        &["message_type"],
        vec![0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1.0, 5.0]
    )
    .unwrap();

    /// REST API message endpoint latency (labels: endpoint=send|receive|list|search)
    pub static ref MESSAGE_API_LATENCY_SECONDS: HistogramVec = register_histogram_vec!(
        "message_api_latency_seconds",
        "Message API endpoint latency in seconds",
        &["endpoint"],
        vec![0.01, 0.05, 0.1, 0.5, 1.0, 2.0, 5.0, 10.0]
    )
    .unwrap();

    /// Message search latency (labels: index_type=fulltext|bm25)
    pub static ref MESSAGE_SEARCH_LATENCY_SECONDS: HistogramVec = register_histogram_vec!(
        "message_search_latency_seconds",
        "Message search latency in seconds",
        &["index_type"],
        vec![0.01, 0.05, 0.1, 0.5, 1.0, 2.0, 5.0]
    )
    .unwrap();

    /// Message delivery latency (time from send to broadcast)
    pub static ref MESSAGE_DELIVERY_LATENCY_SECONDS: HistogramVec = register_histogram_vec!(
        "message_delivery_latency_seconds",
        "Message delivery latency in seconds",
        &["delivery_type"]  // direct|queue|broadcast
    )
    .unwrap();

    // ======================
    // P0: Database Metrics
    // ======================

    /// Current active database connections
    pub static ref DB_CONNECTIONS_ACTIVE: Gauge = register_gauge!(
        "db_connections_active",
        "Current active database connections"
    )
    .unwrap();

    /// Current idle database connections
    pub static ref DB_CONNECTIONS_IDLE: Gauge = register_gauge!(
        "db_connections_idle",
        "Current idle database connections"
    )
    .unwrap();

    /// Requests waiting for available database connection
    pub static ref DB_CONNECTIONS_WAITING: Gauge = register_gauge!(
        "db_connections_waiting",
        "Requests waiting for available database connection"
    )
    .unwrap();

    /// Time to acquire a database connection (in seconds)
    pub static ref DB_CONNECTION_ACQUIRE_SECONDS: Histogram = register_histogram!(
        "db_connection_acquire_seconds",
        "Time to acquire a database connection",
        vec![0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1.0]
    )
    .unwrap();

    /// Database query execution time (in seconds, labels: query_type=select|insert|update|delete)
    pub static ref DB_QUERY_DURATION_SECONDS: HistogramVec = register_histogram_vec!(
        "db_query_duration_seconds",
        "Database query execution time in seconds",
        &["query_type"],
        vec![0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1.0, 5.0]
    )
    .unwrap();

    // ======================
    // P0: Redis Metrics
    // ======================

    /// Redis cache hits (labels: cache_key_prefix=user|conversation|message)
    pub static ref REDIS_CACHE_HITS_TOTAL: CounterVec = register_counter_vec!(
        "redis_cache_hits_total",
        "Redis cache hits by key prefix",
        &["cache_key_prefix"]
    )
    .unwrap();

    /// Redis cache misses (labels: cache_key_prefix=user|conversation|message)
    pub static ref REDIS_CACHE_MISSES_TOTAL: CounterVec = register_counter_vec!(
        "redis_cache_misses_total",
        "Redis cache misses by key prefix",
        &["cache_key_prefix"]
    )
    .unwrap();

    /// Total keys evicted from Redis due to memory pressure
    pub static ref REDIS_EVICTIONS_TOTAL: Gauge = register_gauge!(
        "redis_evictions_total",
        "Total keys evicted from Redis due to memory pressure"
    )
    .unwrap();

    /// Redis GET operation latency (in seconds)
    pub static ref REDIS_GET_LATENCY_SECONDS: Histogram = register_histogram!(
        "redis_get_latency_seconds",
        "Redis GET operation latency in seconds",
        vec![0.0001, 0.0005, 0.001, 0.005, 0.01]
    )
    .unwrap();

    /// Redis SET operation latency (in seconds)
    pub static ref REDIS_SET_LATENCY_SECONDS: Histogram = register_histogram!(
        "redis_set_latency_seconds",
        "Redis SET operation latency in seconds",
        vec![0.0001, 0.0005, 0.001, 0.005, 0.01]
    )
    .unwrap();

    /// Redis memory usage in bytes
    pub static ref REDIS_MEMORY_USED_BYTES: Gauge = register_gauge!(
        "redis_memory_used_bytes",
        "Redis memory usage in bytes"
    )
    .unwrap();

    // ======================
    // P0: Message Size Metrics
    // ======================

    /// WebSocket message payload size in bytes
    pub static ref MESSAGE_SIZE_BYTES_HISTOGRAM: Histogram = register_histogram!(
        "message_size_bytes",
        "WebSocket message payload size in bytes",
        vec![100.0, 1000.0, 10000.0, 100000.0, 1000000.0, 10000000.0]
    )
    .unwrap();

    /// Messages exceeding size limits (labels: size_category=medium|large|huge)
    pub static ref OVERSIZED_MESSAGE_TOTAL: CounterVec = register_counter_vec!(
        "oversized_message_total",
        "Messages exceeding size limits",
        &["size_category"]
    )
    .unwrap();

    // ======================
    // P1: Rate & Queue Metrics
    // ======================

    /// Global message rate (messages per second)
    pub static ref GLOBAL_MESSAGE_RATE_GAUGE: Gauge = register_gauge!(
        "global_message_rate_per_second",
        "Global message rate in messages per second"
    )
    .unwrap();

    /// Count of times message rate exceeded threshold
    pub static ref MESSAGE_RATE_SPIKE_TOTAL: Counter = register_counter!(
        "message_rate_spike_total",
        "Number of times message rate exceeded threshold"
    )
    .unwrap();

    /// Count of users exceeding per-user rate limit
    pub static ref HIGH_RATE_USERS_TOTAL: Counter = register_counter!(
        "high_rate_users_total",
        "Number of users exceeding rate limit"
    )
    .unwrap();

    /// Time message spent in processing queue (in seconds)
    pub static ref MESSAGE_AGE_IN_QUEUE_SECONDS: Histogram = register_histogram!(
        "message_age_in_queue_seconds",
        "Time message spent in processing queue in seconds",
        vec![0.1, 0.5, 1.0, 5.0, 10.0, 30.0, 60.0]
    )
    .unwrap();

    /// Number of messages behind in queue processing
    pub static ref QUEUE_PROCESSING_LAG_MESSAGES: Gauge = register_gauge!(
        "queue_processing_lag_messages",
        "Number of messages behind in queue processing"
    )
    .unwrap();

    /// Current message consumption rate (messages per second)
    pub static ref QUEUE_CONSUMER_RATE_PER_SECOND: Gauge = register_gauge!(
        "queue_consumer_rate_per_second",
        "Current message consumption rate in messages per second"
    )
    .unwrap();

    /// Total time from send to delivery completion (labels: delivery_path=direct|queue_consumed|broadcast)
    pub static ref MESSAGE_TOTAL_DELIVERY_LATENCY_SECONDS: HistogramVec = register_histogram_vec!(
        "message_total_delivery_latency_seconds",
        "Total time from send to delivery completion in seconds",
        &["delivery_path"],
        vec![0.01, 0.05, 0.1, 0.5, 1.0, 5.0, 10.0]
    )
    .unwrap();
}

/// Initialize all messaging metrics
/// Panics if any metric fails to register (fail-fast behavior)
pub fn init_messaging_metrics() {
    // Register all metrics with global registry
    let registry = super::REGISTRY.clone();

    // Helper macro to fail loudly on registration errors
    macro_rules! register_metric {
        ($registry:expr, $metric:expr, $name:expr) => {
            $registry
                .register(Box::new($metric.clone()))
                .unwrap_or_else(|e| panic!("Failed to register metric '{}': {}", $name, e))
        };
    }

    // === WebSocket & Messaging Metrics ===
    register_metric!(registry, WS_CONNECTIONS_TOTAL.clone(), "ws_connections_total");
    register_metric!(registry, WS_MESSAGES_SENT_TOTAL.clone(), "ws_messages_sent_total");
    register_metric!(registry, WS_MESSAGES_RECEIVED_TOTAL.clone(), "ws_messages_received_total");
    register_metric!(registry, WS_ERRORS_TOTAL.clone(), "ws_errors_total");
    register_metric!(registry, WS_RECONNECTIONS_TOTAL.clone(), "ws_reconnections_total");

    register_metric!(registry, MESSAGES_SENT_TOTAL.clone(), "messages_sent_total");
    register_metric!(registry, MESSAGES_RECEIVED_TOTAL.clone(), "messages_received_total");
    register_metric!(registry, MESSAGE_DELIVERY_FAILURES_TOTAL.clone(), "message_delivery_failures_total");
    register_metric!(registry, CONVERSATIONS_CREATED_TOTAL.clone(), "conversations_created_total");
    register_metric!(registry, MESSAGE_SEARCHES_TOTAL.clone(), "message_searches_total");

    register_metric!(registry, WS_ACTIVE_CONNECTIONS.clone(), "ws_active_connections");
    register_metric!(registry, ACTIVE_CONVERSATIONS.clone(), "active_conversations");
    register_metric!(registry, MESSAGE_QUEUE_DEPTH.clone(), "message_queue_depth");

    register_metric!(registry, WS_MESSAGE_LATENCY_SECONDS.clone(), "ws_message_latency_seconds");
    register_metric!(registry, MESSAGE_API_LATENCY_SECONDS.clone(), "message_api_latency_seconds");
    register_metric!(registry, MESSAGE_SEARCH_LATENCY_SECONDS.clone(), "message_search_latency_seconds");
    register_metric!(registry, MESSAGE_DELIVERY_LATENCY_SECONDS.clone(), "message_delivery_latency_seconds");

    // === P0: Database Metrics ===
    register_metric!(registry, DB_CONNECTIONS_ACTIVE.clone(), "db_connections_active");
    register_metric!(registry, DB_CONNECTIONS_IDLE.clone(), "db_connections_idle");
    register_metric!(registry, DB_CONNECTIONS_WAITING.clone(), "db_connections_waiting");
    register_metric!(registry, DB_CONNECTION_ACQUIRE_SECONDS.clone(), "db_connection_acquire_seconds");
    register_metric!(registry, DB_QUERY_DURATION_SECONDS.clone(), "db_query_duration_seconds");

    // === P0: Redis Metrics ===
    register_metric!(registry, REDIS_CACHE_HITS_TOTAL.clone(), "redis_cache_hits_total");
    register_metric!(registry, REDIS_CACHE_MISSES_TOTAL.clone(), "redis_cache_misses_total");
    register_metric!(registry, REDIS_EVICTIONS_TOTAL.clone(), "redis_evictions_total");
    register_metric!(registry, REDIS_GET_LATENCY_SECONDS.clone(), "redis_get_latency_seconds");
    register_metric!(registry, REDIS_SET_LATENCY_SECONDS.clone(), "redis_set_latency_seconds");
    register_metric!(registry, REDIS_MEMORY_USED_BYTES.clone(), "redis_memory_used_bytes");

    // === P0: Message Size Metrics ===
    register_metric!(registry, MESSAGE_SIZE_BYTES_HISTOGRAM.clone(), "message_size_bytes");
    register_metric!(registry, OVERSIZED_MESSAGE_TOTAL.clone(), "oversized_message_total");

    // === P1: Rate & Queue Metrics ===
    register_metric!(registry, GLOBAL_MESSAGE_RATE_GAUGE.clone(), "global_message_rate_per_second");
    register_metric!(registry, MESSAGE_RATE_SPIKE_TOTAL.clone(), "message_rate_spike_total");
    register_metric!(registry, HIGH_RATE_USERS_TOTAL.clone(), "high_rate_users_total");
    register_metric!(registry, MESSAGE_AGE_IN_QUEUE_SECONDS.clone(), "message_age_in_queue_seconds");
    register_metric!(registry, QUEUE_PROCESSING_LAG_MESSAGES.clone(), "queue_processing_lag_messages");
    register_metric!(registry, QUEUE_CONSUMER_RATE_PER_SECOND.clone(), "queue_consumer_rate_per_second");
    register_metric!(registry, MESSAGE_TOTAL_DELIVERY_LATENCY_SECONDS.clone(), "message_total_delivery_latency_seconds");
}
