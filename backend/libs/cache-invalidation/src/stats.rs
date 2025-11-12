//! Statistics tracking for cache invalidation operations

use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

/// Statistics for invalidation operations
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InvalidationStats {
    pub messages_published: u64,
    pub messages_received: u64,
    pub errors: u64,
    pub latency_p50_ms: f64,
    pub latency_p99_ms: f64,
}

impl Default for InvalidationStats {
    fn default() -> Self {
        Self {
            messages_published: 0,
            messages_received: 0,
            errors: 0,
            latency_p50_ms: 0.0,
            latency_p99_ms: 0.0,
        }
    }
}

/// Thread-safe statistics collector
#[derive(Clone)]
pub struct StatsCollector {
    messages_published: Arc<AtomicU64>,
    messages_received: Arc<AtomicU64>,
    errors: Arc<AtomicU64>,
    latencies: Arc<std::sync::Mutex<Vec<f64>>>,
}

impl Default for StatsCollector {
    fn default() -> Self {
        Self::new()
    }
}

impl StatsCollector {
    /// Create new statistics collector
    pub fn new() -> Self {
        Self {
            messages_published: Arc::new(AtomicU64::new(0)),
            messages_received: Arc::new(AtomicU64::new(0)),
            errors: Arc::new(AtomicU64::new(0)),
            latencies: Arc::new(std::sync::Mutex::new(Vec::new())),
        }
    }

    /// Record message published
    pub fn record_publish(&self) {
        self.messages_published.fetch_add(1, Ordering::Relaxed);
    }

    /// Record message received
    pub fn record_receive(&self) {
        self.messages_received.fetch_add(1, Ordering::Relaxed);
    }

    /// Record error
    pub fn record_error(&self) {
        self.errors.fetch_add(1, Ordering::Relaxed);
    }

    /// Record latency (in milliseconds)
    pub fn record_latency(&self, latency_ms: f64) {
        if let Ok(mut latencies) = self.latencies.lock() {
            latencies.push(latency_ms);
            // Keep only last 1000 samples to prevent unbounded growth
            if latencies.len() > 1000 {
                latencies.drain(0..500);
            }
        }
    }

    /// Get current statistics snapshot
    pub fn snapshot(&self) -> InvalidationStats {
        let messages_published = self.messages_published.load(Ordering::Relaxed);
        let messages_received = self.messages_received.load(Ordering::Relaxed);
        let errors = self.errors.load(Ordering::Relaxed);

        let (p50, p99) = if let Ok(mut latencies) = self.latencies.lock() {
            if latencies.is_empty() {
                (0.0, 0.0)
            } else {
                latencies.sort_by(|a, b| a.partial_cmp(b).unwrap());
                let p50_idx = (latencies.len() as f64 * 0.50) as usize;
                let p99_idx = (latencies.len() as f64 * 0.99) as usize;
                (
                    latencies[p50_idx.min(latencies.len() - 1)],
                    latencies[p99_idx.min(latencies.len() - 1)],
                )
            }
        } else {
            (0.0, 0.0)
        };

        InvalidationStats {
            messages_published,
            messages_received,
            errors,
            latency_p50_ms: p50,
            latency_p99_ms: p99,
        }
    }

    /// Reset all statistics
    pub fn reset(&self) {
        self.messages_published.store(0, Ordering::Relaxed);
        self.messages_received.store(0, Ordering::Relaxed);
        self.errors.store(0, Ordering::Relaxed);
        if let Ok(mut latencies) = self.latencies.lock() {
            latencies.clear();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_stats_default() {
        let stats = InvalidationStats::default();
        assert_eq!(stats.messages_published, 0);
        assert_eq!(stats.messages_received, 0);
        assert_eq!(stats.errors, 0);
        assert_eq!(stats.latency_p50_ms, 0.0);
        assert_eq!(stats.latency_p99_ms, 0.0);
    }

    #[test]
    fn test_stats_collector_new() {
        let collector = StatsCollector::new();
        let stats = collector.snapshot();
        assert_eq!(stats.messages_published, 0);
        assert_eq!(stats.messages_received, 0);
        assert_eq!(stats.errors, 0);
    }

    #[test]
    fn test_stats_collector_record_publish() {
        let collector = StatsCollector::new();
        collector.record_publish();
        collector.record_publish();
        let stats = collector.snapshot();
        assert_eq!(stats.messages_published, 2);
    }

    #[test]
    fn test_stats_collector_record_receive() {
        let collector = StatsCollector::new();
        collector.record_receive();
        collector.record_receive();
        collector.record_receive();
        let stats = collector.snapshot();
        assert_eq!(stats.messages_received, 3);
    }

    #[test]
    fn test_stats_collector_record_error() {
        let collector = StatsCollector::new();
        collector.record_error();
        let stats = collector.snapshot();
        assert_eq!(stats.errors, 1);
    }

    #[test]
    fn test_stats_collector_record_latency() {
        let collector = StatsCollector::new();
        collector.record_latency(10.0);
        collector.record_latency(20.0);
        collector.record_latency(30.0);
        collector.record_latency(40.0);
        collector.record_latency(50.0);

        let stats = collector.snapshot();
        assert!(stats.latency_p50_ms > 0.0);
        assert!(stats.latency_p99_ms > 0.0);
        assert!(stats.latency_p99_ms >= stats.latency_p50_ms);
    }

    #[test]
    fn test_stats_collector_reset() {
        let collector = StatsCollector::new();
        collector.record_publish();
        collector.record_receive();
        collector.record_error();
        collector.record_latency(10.0);

        collector.reset();

        let stats = collector.snapshot();
        assert_eq!(stats.messages_published, 0);
        assert_eq!(stats.messages_received, 0);
        assert_eq!(stats.errors, 0);
    }

    #[test]
    fn test_stats_collector_latency_percentiles() {
        let collector = StatsCollector::new();

        // Add 100 latency samples
        for i in 1..=100 {
            collector.record_latency(i as f64);
        }

        let stats = collector.snapshot();
        // P50 of 100 samples is at index 50 (0-indexed), which is the 51st value
        assert!(stats.latency_p50_ms >= 49.0 && stats.latency_p50_ms <= 51.0);
        assert!(stats.latency_p99_ms >= 98.0 && stats.latency_p99_ms <= 100.0);
    }

    #[test]
    fn test_stats_collector_clone() {
        let collector1 = StatsCollector::new();
        collector1.record_publish();

        let collector2 = collector1.clone();
        collector2.record_publish();

        // Both should share the same underlying data
        let stats = collector1.snapshot();
        assert_eq!(stats.messages_published, 2);
    }

    #[test]
    fn test_stats_serialization() {
        let stats = InvalidationStats {
            messages_published: 100,
            messages_received: 200,
            errors: 5,
            latency_p50_ms: 10.5,
            latency_p99_ms: 50.2,
        };

        let json = serde_json::to_string(&stats).unwrap();
        let deserialized: InvalidationStats = serde_json::from_str(&json).unwrap();

        assert_eq!(stats.messages_published, deserialized.messages_published);
        assert_eq!(stats.messages_received, deserialized.messages_received);
        assert_eq!(stats.errors, deserialized.errors);
        assert_eq!(stats.latency_p50_ms, deserialized.latency_p50_ms);
        assert_eq!(stats.latency_p99_ms, deserialized.latency_p99_ms);
    }
}
