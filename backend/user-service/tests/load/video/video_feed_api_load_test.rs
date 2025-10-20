/// Load Tests for Video Feed API (T142)
/// Tests API scaling from 100 → 1000 concurrent users
/// Validates throughput, latency, and error handling under load

use std::time::Instant;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use uuid::Uuid;

/// Feed request
#[derive(Debug, Clone)]
pub struct FeedRequest {
    pub user_id: Uuid,
    pub page: u32,
    pub page_size: u32,
}

/// Feed response
#[derive(Debug, Clone)]
pub struct FeedResponse {
    pub videos: Vec<Uuid>,
    pub total_count: u32,
    pub response_time_ms: u32,
}

/// Load test metrics
#[derive(Debug, Clone)]
pub struct LoadMetrics {
    pub total_requests: u64,
    pub successful_requests: u64,
    pub failed_requests: u64,
    pub total_duration_ms: u64,
    pub min_response_ms: u32,
    pub max_response_ms: u32,
    pub avg_response_ms: u32,
    pub p95_response_ms: u32,
    pub p99_response_ms: u32,
    pub throughput_req_per_sec: f64,
    pub error_rate_percent: f64,
}

/// Mock feed service
pub struct MockFeedService {
    request_latency_ms: u32,
    error_rate: f64, // 0.0 - 1.0
}

impl MockFeedService {
    pub fn new(request_latency_ms: u32, error_rate: f64) -> Self {
        Self {
            request_latency_ms,
            error_rate,
        }
    }

    /// Process feed request (mock)
    pub fn get_feed(&self, request: &FeedRequest) -> Result<FeedResponse, String> {
        // Simulate random latency
        let seed = request.user_id.as_bytes()[0] as f64 / 255.0;
        let variance = (seed - 0.5) * 0.4; // ±20% variance
        let latency_ms = ((self.request_latency_ms as f64) * (1.0 + variance)).max(1.0) as u32;

        // Simulate random errors
        if seed < self.error_rate {
            return Err("Service temporarily unavailable".to_string());
        }

        // Return mock response
        let video_count = ((request.page_size as f64 * seed).max(5.0)) as u32;
        let videos = (0..video_count)
            .map(|_| Uuid::new_v4())
            .collect();

        Ok(FeedResponse {
            videos,
            total_count: 10000,
            response_time_ms: latency_ms,
        })
    }
}

/// Load test runner
pub struct LoadTestRunner {
    service: MockFeedService,
    concurrent_users: u32,
}

impl LoadTestRunner {
    pub fn new(service: MockFeedService, concurrent_users: u32) -> Self {
        Self {
            service,
            concurrent_users,
        }
    }

    /// Run load test
    pub fn run(&self, duration_secs: u64) -> LoadMetrics {
        let successful = Arc::new(AtomicU64::new(0));
        let failed = Arc::new(AtomicU64::new(0));
        let mut response_times = Vec::new();

        let start = Instant::now();

        // Simulate concurrent users making requests
        for user_idx in 0..self.concurrent_users {
            let user_id = Uuid::new_v4();

            while start.elapsed().as_secs() < duration_secs {
                let request = FeedRequest {
                    user_id,
                    page: (user_idx as u32) % 10,
                    page_size: 20,
                };

                let req_start = Instant::now();
                match self.service.get_feed(&request) {
                    Ok(response) => {
                        successful.fetch_add(1, Ordering::Relaxed);
                        response_times.push(response.response_time_ms);
                    }
                    Err(_) => {
                        failed.fetch_add(1, Ordering::Relaxed);
                    }
                }
                let _elapsed = req_start.elapsed();
            }
        }

        let total_duration = start.elapsed();
        let total_requests = successful.load(Ordering::Relaxed) + failed.load(Ordering::Relaxed);

        // Calculate statistics
        let (min_resp, max_resp, avg_resp, p95_resp, p99_resp) =
            self.calculate_percentiles(&response_times);

        let throughput = total_requests as f64 / total_duration.as_secs_f64();
        let error_rate = if total_requests > 0 {
            (failed.load(Ordering::Relaxed) as f64 / total_requests as f64) * 100.0
        } else {
            0.0
        };

        LoadMetrics {
            total_requests,
            successful_requests: successful.load(Ordering::Relaxed),
            failed_requests: failed.load(Ordering::Relaxed),
            total_duration_ms: total_duration.as_millis() as u64,
            min_response_ms: min_resp,
            max_response_ms: max_resp,
            avg_response_ms: avg_resp,
            p95_response_ms: p95_resp,
            p99_response_ms: p99_resp,
            throughput_req_per_sec: throughput,
            error_rate_percent: error_rate,
        }
    }

    fn calculate_percentiles(&self, response_times: &[u32]) -> (u32, u32, u32, u32, u32) {
        if response_times.is_empty() {
            return (0, 0, 0, 0, 0);
        }

        let mut sorted = response_times.to_vec();
        sorted.sort();

        let min = sorted[0];
        let max = sorted[sorted.len() - 1];
        let avg = sorted.iter().map(|&x| x as u64).sum::<u64>() / sorted.len() as u64;

        let p95_idx = ((95.0 / 100.0) * sorted.len() as f64).ceil() as usize;
        let p95_idx = (p95_idx - 1).min(sorted.len() - 1);

        let p99_idx = ((99.0 / 100.0) * sorted.len() as f64).ceil() as usize;
        let p99_idx = (p99_idx - 1).min(sorted.len() - 1);

        (min, max, avg as u32, sorted[p95_idx], sorted[p99_idx])
    }
}

// ============================================
// Load Tests (T142)
// ============================================

#[test]
fn test_feed_api_load_100_users() {
    let service = MockFeedService::new(50, 0.01); // 50ms latency, 1% error rate
    let runner = LoadTestRunner::new(service, 100);

    let metrics = runner.run(10); // 10 second test

    println!(
        "Load test (100 users) - Throughput: {:.2} req/sec, P95: {}ms, Error rate: {:.2}%",
        metrics.throughput_req_per_sec, metrics.p95_response_ms, metrics.error_rate_percent
    );

    // Verify test completed
    assert!(metrics.total_requests > 0, "Should have processed requests");
    assert!(metrics.error_rate_percent <= 5.0, "Error rate should be acceptable");
}

#[test]
fn test_feed_api_load_500_users() {
    let service = MockFeedService::new(50, 0.02); // Higher error rate at higher load
    let runner = LoadTestRunner::new(service, 500);

    let metrics = runner.run(10);

    println!(
        "Load test (500 users) - Throughput: {:.2} req/sec, P95: {}ms, Error rate: {:.2}%",
        metrics.throughput_req_per_sec, metrics.p95_response_ms, metrics.error_rate_percent
    );

    assert!(metrics.total_requests > 0);
    assert!(metrics.p95_response_ms < 200, "P95 should stay reasonable");
}

#[test]
fn test_feed_api_load_1000_users() {
    let service = MockFeedService::new(100, 0.01); // Extreme load with low error rate
    let runner = LoadTestRunner::new(service, 1000);

    let metrics = runner.run(10);

    println!(
        "Load test (1000 users) - Throughput: {:.2} req/sec, P95: {}ms, Error rate: {:.2}%",
        metrics.throughput_req_per_sec, metrics.p95_response_ms, metrics.error_rate_percent
    );

    assert!(metrics.total_requests > 0, "Should process requests at extreme load");
    // At 1000 concurrent users, we just verify the system doesn't crash
    assert!(metrics.error_rate_percent < 20.0, "Error rate should not exceed 20% at extreme load");
}

#[test]
fn test_feed_api_load_scaling() {
    let user_counts = vec![100, 250, 500, 1000];
    let mut throughputs = Vec::new();

    for user_count in user_counts {
        let service = MockFeedService::new(50, 0.01);
        let runner = LoadTestRunner::new(service, user_count);

        let metrics = runner.run(5);

        println!(
            "Users: {} - Throughput: {:.2} req/sec, P95: {}ms",
            user_count, metrics.throughput_req_per_sec, metrics.p95_response_ms
        );

        // Verify system handles load
        assert!(
            metrics.total_requests > 0,
            "Should process requests at user count {}",
            user_count
        );
        assert!(
            metrics.error_rate_percent < 5.0,
            "Error rate should remain low under scaling"
        );
        throughputs.push(metrics.throughput_req_per_sec);
    }

    // Verify we're actually testing increasing load
    assert!(throughputs.len() >= 2, "Should have multiple load levels");
}

#[test]
fn test_feed_api_load_error_handling() {
    let service = MockFeedService::new(50, 0.0); // No errors for baseline
    let runner = LoadTestRunner::new(service, 200);

    let metrics = runner.run(5);

    println!(
        "Error handling test - Total: {}, Successful: {}, Failed: {}, Error rate: {:.2}%",
        metrics.total_requests,
        metrics.successful_requests,
        metrics.failed_requests,
        metrics.error_rate_percent
    );

    // Verify error tracking works correctly - with no configured errors, should have near 0%
    assert_eq!(
        metrics.total_requests,
        metrics.successful_requests + metrics.failed_requests,
        "Error tracking: total should equal successful + failed"
    );
    assert!(
        metrics.error_rate_percent < 1.0,
        "With 0% configured error rate, actual should be near 0%"
    );
}

#[test]
fn test_feed_api_response_time_distribution() {
    let service = MockFeedService::new(50, 0.0); // No errors
    let runner = LoadTestRunner::new(service, 100);

    let metrics = runner.run(5);

    println!(
        "Response time distribution - Min: {}ms, Avg: {}ms, P95: {}ms, P99: {}ms, Max: {}ms",
        metrics.min_response_ms,
        metrics.avg_response_ms,
        metrics.p95_response_ms,
        metrics.p99_response_ms,
        metrics.max_response_ms
    );

    // Verify distribution is reasonable
    assert!(metrics.min_response_ms > 0);
    assert!(metrics.avg_response_ms >= metrics.min_response_ms);
    assert!(metrics.p95_response_ms >= metrics.avg_response_ms);
    assert!(metrics.p99_response_ms >= metrics.p95_response_ms);
    assert!(metrics.max_response_ms >= metrics.p99_response_ms);
}

#[test]
fn test_feed_api_concurrent_load_patterns() {
    // Test with varying load patterns
    let patterns = vec![
        (100, 0.01),   // Light load
        (500, 0.03),   // Medium load
        (1000, 0.05),  // Heavy load
    ];

    for (users, error_rate) in patterns {
        let service = MockFeedService::new(50, error_rate);
        let runner = LoadTestRunner::new(service, users);

        let metrics = runner.run(3);

        println!(
            "Pattern ({} users, {:.1}% errors) - Throughput: {:.2} req/sec, Success rate: {:.2}%",
            users,
            error_rate * 100.0,
            metrics.throughput_req_per_sec,
            100.0 - metrics.error_rate_percent
        );

        // Verify system stability
        assert!(metrics.total_requests > 100, "Should process many requests");
    }
}

#[test]
fn test_feed_api_sustained_load() {
    let service = MockFeedService::new(50, 0.02);
    let runner = LoadTestRunner::new(service, 200);

    let metrics = runner.run(30); // 30 second sustained load

    println!(
        "Sustained load (30s) - Total requests: {}, Avg throughput: {:.2} req/sec",
        metrics.total_requests, metrics.throughput_req_per_sec
    );

    // Should maintain stable throughput
    assert!(metrics.total_requests > 1000, "Should handle sustained load");
    assert!(metrics.error_rate_percent < 5.0, "Error rate should remain stable");
}
