//! Performance Benchmark Tests
//!
//! Purpose: Detect performance regression, not enforce exact SLOs
//! Strategy: Record current baseline, fail if performance degrades > 50%
//!
//! Coverage:
//! 1. Feed API P95 latency should not regress significantly
//! 2. Events throughput should sustain 1k events/sec without loss
//!
//! Run: cargo test --test performance_benchmark_test -- --nocapture
//! Expected Duration: ~60s per test

use serde_json::json;
use std::collections::HashMap;
use tokio::time::{sleep, Duration, Instant};

mod test_harness;
use test_harness::{ClickHouseClient, FeedApiClient, KafkaProducer, TestEnvironment};

#[tokio::test]
async fn test_feed_api_performance_baseline() {
    // Baseline: Current P95 is ~300ms for ClickHouse query
    // Fail if: P95 > 450ms (50% regression)

    let env = TestEnvironment::new().await;
    let ch = ClickHouseClient::new(&env.ch_url).await;
    let api = FeedApiClient::new(&env.api_url);

    let user_id = "user-perf";

    // Setup: Populate feed with realistic data (1000 posts)
    let mut insert_queries = Vec::new();
    for i in 0..1000 {
        insert_queries.push(format!(
            "INSERT INTO feed_materialized (user_id, post_id, score, rank) VALUES ('{}', 'post-{}', {}, {})",
            user_id, i, 1000.0 - i as f64, i
        ));
    }
    ch.execute_batch(
        &insert_queries
            .iter()
            .map(|s| s.as_str())
            .collect::<Vec<_>>(),
    )
    .await
    .expect("Failed to populate feed");

    // Warmup: 100 requests to eliminate cold start effects
    println!("Warming up...");
    for _ in 0..100 {
        let _ = api.get_feed(user_id, 50).await;
    }

    // Measure: 1000 requests
    println!("Measuring latency...");
    let mut durations = Vec::new();

    for i in 0..1000 {
        let start = Instant::now();
        let _ = api
            .get_feed(user_id, 50)
            .await
            .expect("Feed API should succeed");
        durations.push(start.elapsed());

        if i % 100 == 0 {
            println!("  Progress: {}/1000", i);
        }
    }

    // Calculate percentiles
    durations.sort();
    let p50 = durations[500];
    let p95 = durations[950];
    let p99 = durations[990];

    println!("Results: P50={:?}, P95={:?}, P99={:?}", p50, p95, p99);

    // Baseline and threshold
    let baseline_p95 = Duration::from_millis(300);
    let threshold_p95 = baseline_p95 + baseline_p95 / 2; // 450ms

    // Assert: P95 should not regress by > 50%
    assert!(
        p95 < threshold_p95,
        "Performance regression detected: P95={:?} exceeds threshold {:?} (baseline={:?})",
        p95,
        threshold_p95,
        baseline_p95
    );

    env.cleanup().await;
}

#[tokio::test]
async fn test_events_throughput_sustained() {
    // Baseline: System should handle 1k events/sec for 30s without loss
    // Fail if: Any events are lost (count mismatch)

    let env = TestEnvironment::new().await;
    let kafka = KafkaProducer::new(&env.kafka_brokers).await;
    let ch = ClickHouseClient::new(&env.ch_url).await;

    let start = Instant::now();
    let mut sent_count = 0;
    let test_duration = Duration::from_secs(30);
    let target_rate = 1000; // events/sec

    println!(
        "Sending events at {} events/sec for {:?}...",
        target_rate, test_duration
    );

    // Send events in batches
    while start.elapsed() < test_duration {
        // Send 100 events per batch
        let batch_start = Instant::now();

        for i in 0..100 {
            let event_id = format!("evt-throughput-{:06}", sent_count);
            let event = json!({
                "event_id": event_id,
                "event_type": "like",
                "user_id": "user-throughput",
                "post_id": format!("post-{}", i % 10),
                "timestamp": chrono::Utc::now().to_rfc3339(),
            });

            kafka
                .send("events", event)
                .await
                .expect("Failed to send event to Kafka");

            sent_count += 1;
        }

        // Sleep to maintain rate (1k events/sec = 100 events per 100ms)
        let elapsed = batch_start.elapsed();
        if elapsed < Duration::from_millis(100) {
            sleep(Duration::from_millis(100) - elapsed).await;
        }

        if sent_count % 5000 == 0 {
            println!(
                "  Sent: {} events ({:?} elapsed)",
                sent_count,
                start.elapsed()
            );
        }
    }

    println!("Sent total: {} events in {:?}", sent_count, start.elapsed());

    // Wait for all events to be consumed and written to ClickHouse
    println!("Waiting for events to be processed...");
    sleep(Duration::from_secs(10)).await;

    // Verify: All events should be in ClickHouse
    let received_count: u64 = ch
        .query_one(
            "SELECT count() FROM events WHERE event_id LIKE 'evt-throughput-%'",
            &[],
        )
        .await
        .expect("Failed to query ClickHouse");

    println!("Received: {} events in ClickHouse", received_count);

    // Calculate loss rate
    let loss_rate = (sent_count - received_count as usize) as f64 / sent_count as f64 * 100.0;

    // Assert: No events should be lost (allow 0.1% tolerance for Kafka/CH eventual consistency)
    assert!(
        loss_rate < 0.1,
        "Event loss detected: sent={}, received={}, loss={:.2}%",
        sent_count,
        received_count,
        loss_rate
    );

    env.cleanup().await;
}

#[tokio::test]
#[ignore] // This is expensive, run manually with: cargo test --test performance_benchmark_test -- --ignored
async fn test_feed_api_under_concurrent_load() {
    // Stress test: 100 concurrent users calling Feed API
    // Baseline: P95 should stay < 500ms under load

    let env = TestEnvironment::new().await;
    let api = FeedApiClient::new(&env.api_url);

    let num_users = 100;
    let requests_per_user = 50;

    println!(
        "Starting concurrent load test: {} users × {} requests",
        num_users, requests_per_user
    );

    let start = Instant::now();
    let mut handles = Vec::new();

    for user_id in 0..num_users {
        let api_clone = api.clone();
        let handle = tokio::spawn(async move {
            let mut durations = Vec::new();

            for _ in 0..requests_per_user {
                let req_start = Instant::now();
                let _ = api_clone.get_feed(&format!("user-{}", user_id), 50).await;
                durations.push(req_start.elapsed());
            }

            durations
        });
        handles.push(handle);
    }

    // Wait for all users to finish
    let mut all_durations = Vec::new();
    for handle in handles {
        all_durations.extend(handle.await.unwrap());
    }

    let total_elapsed = start.elapsed();

    all_durations.sort();
    let p95 = all_durations[all_durations.len() * 95 / 100];

    println!("Concurrent load test completed in {:?}", total_elapsed);
    println!("Total requests: {}, P95={:?}", all_durations.len(), p95);

    assert!(
        p95 < Duration::from_millis(500),
        "P95 under concurrent load should be < 500ms: got {:?}",
        p95
    );

    env.cleanup().await;
}
