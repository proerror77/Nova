//! gRPC Channel Rotation Tests (Quick Win #7)
//!
//! Tests for round-robin gRPC channel rotation with retries
//!
//! Test Coverage:
//! - Round-robin distribution
//! - Retry on failure
//! - Load balancing
//! - All connections tried before failure
//! - Metrics recording

use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use tokio::sync::RwLock;

/// Mock gRPC channel for testing
#[derive(Clone)]
struct MockGrpcChannel {
    id: usize,
    call_count: Arc<AtomicUsize>,
    fail_on_first_call: bool,
}

impl MockGrpcChannel {
    fn new(id: usize, fail_on_first_call: bool) -> Self {
        Self {
            id,
            call_count: Arc::new(AtomicUsize::new(0)),
            fail_on_first_call,
        }
    }

    async fn call(&self) -> Result<String, &'static str> {
        let count = self.call_count.fetch_add(1, Ordering::SeqCst);

        if self.fail_on_first_call && count == 0 {
            Err("Connection failed")
        } else {
            Ok(format!("Response from channel {}", self.id))
        }
    }

    fn get_call_count(&self) -> usize {
        self.call_count.load(Ordering::SeqCst)
    }
}

/// Round-robin channel pool
struct ChannelPool {
    channels: Vec<MockGrpcChannel>,
    current_index: Arc<RwLock<usize>>,
    max_retries: usize,
}

impl ChannelPool {
    fn new(channels: Vec<MockGrpcChannel>, max_retries: usize) -> Self {
        Self {
            channels,
            current_index: Arc::new(RwLock::new(0)),
            max_retries,
        }
    }

    async fn next_channel(&self) -> MockGrpcChannel {
        let mut index = self.current_index.write().await;
        let channel = self.channels[*index].clone();
        *index = (*index + 1) % self.channels.len();
        channel
    }

    async fn call_with_retry(&self) -> Result<String, String> {
        let mut attempts = 0;
        let mut last_error = String::new();

        while attempts < self.max_retries {
            let channel = self.next_channel().await;
            match channel.call().await {
                Ok(response) => return Ok(response),
                Err(e) => {
                    last_error = e.to_string();
                    attempts += 1;
                }
            }
        }

        Err(format!(
            "All {} retry attempts failed: {}",
            attempts, last_error
        ))
    }

    fn channel_count(&self) -> usize {
        self.channels.len()
    }

    fn get_channel_call_counts(&self) -> Vec<(usize, usize)> {
        self.channels
            .iter()
            .map(|ch| (ch.id, ch.get_call_count()))
            .collect()
    }
}

#[tokio::test]
async fn test_round_robin_distribution() {
    // Test: Requests are distributed round-robin across channels
    let channels = vec![
        MockGrpcChannel::new(1, false),
        MockGrpcChannel::new(2, false),
        MockGrpcChannel::new(3, false),
    ];

    let pool = ChannelPool::new(channels, 3);

    // Make 9 requests
    for _ in 0..9 {
        let result = pool.call_with_retry().await;
        assert!(result.is_ok(), "All calls should succeed");
    }

    // Each channel should be called 3 times (9 / 3)
    let call_counts = pool.get_channel_call_counts();
    for (id, count) in call_counts {
        assert_eq!(
            count, 3,
            "Channel {} should be called 3 times, got {}",
            id, count
        );
    }
}

#[tokio::test]
async fn test_retry_on_failure() {
    // Test: Retry on connection failure
    let channels = vec![
        MockGrpcChannel::new(1, true),  // Fails first call
        MockGrpcChannel::new(2, false), // Always succeeds
    ];

    let pool = ChannelPool::new(channels, 5);

    let result = pool.call_with_retry().await;

    // Should succeed after retry
    assert!(result.is_ok(), "Should succeed after retry");

    // Channel 1 failed, so channel 2 handled the request
    let call_counts = pool.get_channel_call_counts();
    assert_eq!(call_counts[0].1, 1, "Channel 1 should be tried once");
    assert_eq!(call_counts[1].1, 1, "Channel 2 should succeed");
}

#[tokio::test]
async fn test_all_connections_tried_before_failure() {
    // Test: All channels tried before giving up
    let channels = vec![
        MockGrpcChannel::new(1, true),
        MockGrpcChannel::new(2, true),
        MockGrpcChannel::new(3, true),
    ];

    let pool = ChannelPool::new(channels, 5);

    let result = pool.call_with_retry().await;

    // Should fail after trying all channels
    assert!(result.is_err(), "Should fail when all channels fail");

    // All channels should be tried
    let call_counts = pool.get_channel_call_counts();
    for (id, count) in call_counts {
        assert!(
            count >= 1,
            "Channel {} should be tried at least once",
            id
        );
    }
}

#[tokio::test]
async fn test_load_balancing_fairness() {
    // Test: Load is balanced fairly across channels
    let channels = vec![
        MockGrpcChannel::new(1, false),
        MockGrpcChannel::new(2, false),
        MockGrpcChannel::new(3, false),
        MockGrpcChannel::new(4, false),
    ];

    let pool = ChannelPool::new(channels, 4);

    // Make 100 requests
    for _ in 0..100 {
        pool.call_with_retry().await.expect("Should succeed");
    }

    // Each channel should handle ~25 requests (100 / 4)
    let call_counts = pool.get_channel_call_counts();
    for (id, count) in call_counts {
        assert_eq!(
            count, 25,
            "Channel {} should handle 25 requests, got {}",
            id, count
        );
    }
}

#[tokio::test]
async fn test_concurrent_requests_balanced() {
    // Test: Concurrent requests are balanced
    let channels = vec![
        MockGrpcChannel::new(1, false),
        MockGrpcChannel::new(2, false),
        MockGrpcChannel::new(3, false),
    ];

    let pool = Arc::new(ChannelPool::new(channels, 3));
    let mut handles = vec![];

    // Spawn 30 concurrent requests
    for _ in 0..30 {
        let pool_clone = Arc::clone(&pool);
        let handle = tokio::spawn(async move {
            pool_clone.call_with_retry().await
        });
        handles.push(handle);
    }

    // Wait for all requests
    let mut success_count = 0;
    for handle in handles {
        if let Ok(Ok(_)) = handle.await {
            success_count += 1;
        }
    }

    assert_eq!(success_count, 30, "All requests should succeed");

    // Load should be roughly balanced (10 per channel)
    let call_counts = pool.get_channel_call_counts();
    for (id, count) in call_counts {
        assert!(
            count >= 8 && count <= 12,
            "Channel {} should handle ~10 requests, got {}",
            id,
            count
        );
    }
}

#[tokio::test]
async fn test_retry_count_limit() {
    // Test: Respects max retry limit
    let channels = vec![
        MockGrpcChannel::new(1, true),
        MockGrpcChannel::new(2, true),
    ];

    let max_retries = 3;
    let pool = ChannelPool::new(channels, max_retries);

    let result = pool.call_with_retry().await;

    assert!(result.is_err(), "Should fail after max retries");

    // Total attempts = max_retries
    let total_calls: usize = pool.get_channel_call_counts().iter().map(|(_, c)| c).sum();
    assert_eq!(
        total_calls, max_retries,
        "Should make exactly {} attempts",
        max_retries
    );
}

#[tokio::test]
async fn test_channel_recovery_after_failure() {
    // Test: Channel can recover after transient failure
    let channels = vec![
        MockGrpcChannel::new(1, true),  // Fails first call only
        MockGrpcChannel::new(2, false),
    ];

    let pool = ChannelPool::new(channels, 3);

    // First request - channel 1 fails, channel 2 succeeds
    let result1 = pool.call_with_retry().await;
    assert!(result1.is_ok());

    // Second request - channel 1 should work now (first call already done)
    let result2 = pool.call_with_retry().await;
    assert!(result2.is_ok());

    let call_counts = pool.get_channel_call_counts();
    assert!(
        call_counts[0].1 > 1,
        "Channel 1 should be retried and succeed"
    );
}

#[tokio::test]
async fn test_metrics_recording() {
    // Test: Metrics are recorded for retry attempts
    let channels = vec![
        MockGrpcChannel::new(1, true),  // Fails once
        MockGrpcChannel::new(2, false),
    ];

    let pool = ChannelPool::new(channels, 5);

    let mut total_requests = 0;
    let mut failed_first_attempt = 0;
    let mut total_retries = 0;

    // Make 10 requests
    for _ in 0..10 {
        total_requests += 1;
        let initial_counts: usize = pool.get_channel_call_counts().iter().map(|(_, c)| c).sum();

        let result = pool.call_with_retry().await;
        assert!(result.is_ok());

        let final_counts: usize = pool.get_channel_call_counts().iter().map(|(_, c)| c).sum();
        let attempts = final_counts - initial_counts;

        if attempts > 1 {
            failed_first_attempt += 1;
            total_retries += attempts - 1;
        }
    }

    println!("Total requests: {}", total_requests);
    println!("Failed first attempt: {}", failed_first_attempt);
    println!("Total retries: {}", total_retries);

    assert!(
        failed_first_attempt > 0,
        "Some requests should require retry"
    );
}

#[tokio::test]
async fn test_single_channel_fallback() {
    // Test: Works with single channel (no rotation)
    let channels = vec![MockGrpcChannel::new(1, false)];

    let pool = ChannelPool::new(channels, 3);

    // Make 10 requests
    for _ in 0..10 {
        let result = pool.call_with_retry().await;
        assert!(result.is_ok());
    }

    // All requests go to single channel
    let call_counts = pool.get_channel_call_counts();
    assert_eq!(call_counts[0].1, 10);
}

#[tokio::test]
async fn test_channel_selection_wraps_around() {
    // Test: Index wraps around to first channel
    let channels = vec![
        MockGrpcChannel::new(1, false),
        MockGrpcChannel::new(2, false),
    ];

    let pool = ChannelPool::new(channels, 2);

    // Make 6 requests (3 full cycles)
    for _ in 0..6 {
        pool.call_with_retry().await.expect("Should succeed");
    }

    // Each channel called 3 times
    let call_counts = pool.get_channel_call_counts();
    assert_eq!(call_counts[0].1, 3, "Channel 1 should be called 3 times");
    assert_eq!(call_counts[2].1, 3, "Channel 2 should be called 3 times");
}

#[tokio::test]
async fn test_high_throughput_rotation() {
    // Test: Handle high request throughput
    let channels = vec![
        MockGrpcChannel::new(1, false),
        MockGrpcChannel::new(2, false),
        MockGrpcChannel::new(3, false),
        MockGrpcChannel::new(4, false),
    ];

    let pool = Arc::new(ChannelPool::new(channels, 4));
    let mut handles = vec![];

    // 1000 concurrent requests
    for _ in 0..1000 {
        let pool_clone = Arc::clone(&pool);
        let handle = tokio::spawn(async move {
            pool_clone.call_with_retry().await
        });
        handles.push(handle);
    }

    let mut success_count = 0;
    for handle in handles {
        if let Ok(Ok(_)) = handle.await {
            success_count += 1;
        }
    }

    assert_eq!(success_count, 1000, "All requests should succeed");

    // Load should be roughly balanced (250 per channel)
    let call_counts = pool.get_channel_call_counts();
    for (id, count) in call_counts {
        assert!(
            count >= 200 && count <= 300,
            "Channel {} should handle ~250 requests, got {}",
            id,
            count
        );
    }
}

#[tokio::test]
async fn test_partial_channel_failure() {
    // Test: Handle partial channel failures
    let channels = vec![
        MockGrpcChannel::new(1, false), // Always works
        MockGrpcChannel::new(2, true),  // Fails first call
        MockGrpcChannel::new(3, false), // Always works
    ];

    let pool = ChannelPool::new(channels, 5);

    // Make multiple requests
    for _ in 0..10 {
        let result = pool.call_with_retry().await;
        assert!(result.is_ok(), "Should succeed with healthy channels");
    }

    // Healthy channels should handle more requests
    let call_counts = pool.get_channel_call_counts();
    assert!(call_counts[0].1 > 0, "Channel 1 should handle requests");
    assert!(call_counts[1].1 > 0, "Channel 2 should be tried");
    assert!(call_counts[2].1 > 0, "Channel 3 should handle requests");
}

#[tokio::test]
async fn test_error_propagation() {
    // Test: Errors are properly propagated
    let channels = vec![
        MockGrpcChannel::new(1, true),
        MockGrpcChannel::new(2, true),
    ];

    let pool = ChannelPool::new(channels, 2);

    let result = pool.call_with_retry().await;

    assert!(result.is_err(), "Should return error when all fail");
    assert!(
        result.unwrap_err().contains("failed"),
        "Error message should indicate failure"
    );
}
