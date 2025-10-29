use lazy_static::lazy_static;
use prometheus::{
    register_histogram_vec, register_int_counter_vec, HistogramVec, IntCounterVec,
};

lazy_static! {
    /// Duration of feed requests by source (clickhouse, fallback_postgres, cache).
    pub static ref FEED_REQUEST_DURATION_SECONDS: HistogramVec = register_histogram_vec!(
        "feed_request_duration_seconds",
        "Feed request duration segmented by data source",
        &["source"]
    )
    .expect("failed to register feed_request_duration_seconds");

    /// Total feed requests processed by source.
    pub static ref FEED_REQUEST_TOTAL: IntCounterVec = register_int_counter_vec!(
        "feed_request_total",
        "Total feed requests segmented by data source",
        &["source"]
    )
    .expect("failed to register feed_request_total");

    /// Count of candidates considered per source (ClickHouse vs fallback).
    pub static ref FEED_CANDIDATE_COUNT: HistogramVec = register_histogram_vec!(
        "feed_candidate_count",
        "Number of feed candidates evaluated segmented by source",
        &["source"]
    )
    .expect("failed to register feed_candidate_count");

    /// Feed cache events (hit/miss/error).
    pub static ref FEED_CACHE_EVENTS: IntCounterVec = register_int_counter_vec!(
        "feed_cache_events_total",
        "Feed cache events segmented by outcome",
        &["event"]
    )
    .expect("failed to register feed_cache_events_total");

    /// Feed cache write results (success/error).
    pub static ref FEED_CACHE_WRITE_TOTAL: IntCounterVec = register_int_counter_vec!(
        "feed_cache_write_total",
        "Feed cache write attempts segmented by outcome",
        &["result"]
    )
    .expect("failed to register feed_cache_write_total");
}
