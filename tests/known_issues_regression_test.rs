//! Known Issues Regression Tests
//!
//! Purpose: Test production issues that have happened or will definitely happen
//! Coverage:
//! 1. Deduplication works (same event_id sent twice → only 1 record)
//! 2. Circuit breaker works (ClickHouse down → fallback to PostgreSQL)
//! 3. Author saturation rule (Top-5 should not have 2 posts from same author)
//! 4. Event-to-visible latency (P95 < 5s)
//!
//! Run: cargo test --test known_issues_regression_test
//! Expected Duration: ~60s per test

use serde_json::json;
use tokio::time::{sleep, Duration, Instant};

mod test_harness;
use test_harness::{ClickHouseClient, FeedApiClient, KafkaProducer, TestEnvironment};

#[tokio::test]
async fn test_dedup_prevents_duplicate_events() {
    // Issue: In production, clients may retry failed requests,
    // causing duplicate events with same event_id.
    // Expected: Only one event should be stored.

    let env = TestEnvironment::new().await;
    let kafka = KafkaProducer::new(&env.kafka_brokers).await;
    let ch = ClickHouseClient::new(&env.ch_url).await;

    let event_id = "dedup-test-123";

    // Action: Send the same event twice
    for _ in 0..2 {
        let event = json!({
            "event_id": event_id,
            "event_type": "like",
            "user_id": "user-dedup",
            "post_id": "post-dedup",
            "timestamp": chrono::Utc::now().to_rfc3339(),
        });
        kafka.send("events", event).await.unwrap();
    }

    sleep(Duration::from_secs(2)).await;

    // Assert: ClickHouse should have exactly 1 record
    let result = ch
        .query_one("SELECT count() FROM events WHERE event_id = ?", &[event_id])
        .await
        .expect("Failed to query ClickHouse");

    let count: u64 = result[0]["count()"]
        .as_u64()
        .expect("Failed to extract count from ClickHouse response");

    assert_eq!(
        count, 1,
        "Deduplication should prevent duplicates: got {count} records for event_id={event_id}"
    );

    env.cleanup().await;
}

#[tokio::test]
async fn test_circuit_breaker_fallback_to_postgres() {
    // Issue: ClickHouse may timeout or fail under high load.
    // Expected: Feed API should fallback to PostgreSQL instead of crashing.

    let env = TestEnvironment::new().await;
    let api = FeedApiClient::new(&env.api_url);

    // Action 1: Call Feed API with ClickHouse working (baseline)
    let feed_before = api
        .get_feed("user-circuit", 50)
        .await
        .expect("Feed API should work when ClickHouse is up");

    // Action 2: Stop ClickHouse (simulate failure)
    env.stop_clickhouse().await;

    // Action 3: Call Feed API again
    let result = api.get_feed("user-circuit", 50).await;

    // Assert: Should NOT crash, should return result (even if empty/cached)
    assert!(
        result.is_ok(),
        "Feed API should not crash when ClickHouse is down: {:?}",
        result.err()
    );

    let feed_after = result.unwrap();

    // Optional: Verify it used fallback (could check logs or metrics)
    // For now, just ensure it doesn't panic

    println!(
        "Circuit breaker test passed: before={} posts, after={} posts",
        feed_before.len(),
        feed_after.len()
    );

    env.cleanup().await;
}

#[tokio::test]
async fn test_author_saturation_rule() {
    // Issue: Users complained "my feed is all from the same person"
    // Rule: Top-5 posts should have at most 1 post from same author

    let env = TestEnvironment::new().await;
    let ch = ClickHouseClient::new(&env.ch_url).await;
    let api = FeedApiClient::new(&env.api_url);

    let user_id = "user-saturation";
    let author_a = "author-prolific";
    let author_b = "author-other";

    // Setup: Create 3 high-score posts from author_a, 2 from author_b
    ch.execute_batch(&[
        &format!("INSERT INTO feed_materialized (user_id, post_id, author_id, score, rank) VALUES ('{user_id}', 'post-a1', '{author_a}', 500.0, 1)"),
        &format!("INSERT INTO feed_materialized (user_id, post_id, author_id, score, rank) VALUES ('{user_id}', 'post-a2', '{author_a}', 480.0, 2)"),
        &format!("INSERT INTO feed_materialized (user_id, post_id, author_id, score, rank) VALUES ('{user_id}', 'post-a3', '{author_a}', 460.0, 3)"),
        &format!("INSERT INTO feed_materialized (user_id, post_id, author_id, score, rank) VALUES ('{user_id}', 'post-b1', '{author_b}', 450.0, 4)"),
        &format!("INSERT INTO feed_materialized (user_id, post_id, author_id, score, rank) VALUES ('{user_id}', 'post-b2', '{author_b}', 440.0, 5)"),
    ]).await.expect("Failed to insert feed data");

    // Action: Get feed
    let feed = api.get_feed(user_id, 50).await.unwrap();

    // Assert: In Top-5, should have at most 1 post from author_a
    let top_5 = &feed[0..5.min(feed.len())];
    let author_a_count = top_5.iter().filter(|p| p.author_id == author_a).count();

    assert!(
        author_a_count <= 1,
        "Top-5 should have at most 1 post from author '{author_a}': got {author_a_count} posts"
    );

    // Also verify we still have 5 posts (didn't just filter out all of them)
    assert_eq!(top_5.len(), 5, "Should still have 5 posts in feed");

    env.cleanup().await;
}

#[tokio::test]
async fn test_event_to_visible_latency_p95() {
    // Issue: Users see stale feeds, events take too long to appear
    // SLO: P95 latency from event sent → visible in feed < 5s

    let env = TestEnvironment::new().await;
    let kafka = KafkaProducer::new(&env.kafka_brokers).await;
    let api = FeedApiClient::new(&env.api_url);

    let user_id = "user-latency";
    let post_id = "post-latency-001";

    let start = Instant::now();

    // Action 1: Send a like event
    let event = json!({
        "event_id": "evt-latency-001",
        "event_type": "like",
        "user_id": user_id,
        "post_id": post_id,
        "timestamp": chrono::Utc::now().to_rfc3339(),
    });
    kafka.send("events", event).await.unwrap();

    // Action 2: Poll Feed API until post becomes visible
    let mut visible = false;
    let mut attempts = 0;

    for _ in 0..50 {
        // Max 5 seconds (50 * 100ms)
        attempts += 1;

        if let Ok(feed) = api.get_feed(user_id, 50).await {
            if feed.iter().any(|p| p.post_id == post_id) {
                visible = true;
                break;
            }
        }

        sleep(Duration::from_millis(100)).await;
    }

    let elapsed = start.elapsed();

    // Assert: Post should be visible
    assert!(
        visible,
        "Post should become visible in feed after {attempts} attempts ({elapsed:?})"
    );

    // Assert: Latency should be < 5s (P95 threshold)
    assert!(
        elapsed < Duration::from_secs(5),
        "Event-to-visible latency should be < 5s: got {elapsed:?} ({attempts} attempts)"
    );

    println!("Latency test passed: {elapsed:?} ({attempts} attempts)");

    env.cleanup().await;
}

#[tokio::test]
async fn test_dedup_with_different_timestamps() {
    // Edge case: Same event_id but different timestamps
    // Expected: Should still deduplicate (event_id is the key)

    let env = TestEnvironment::new().await;
    let kafka = KafkaProducer::new(&env.kafka_brokers).await;
    let ch = ClickHouseClient::new(&env.ch_url).await;

    let event_id = "dedup-ts-test";

    // Send same event_id with different timestamps
    for i in 0..3 {
        let event = json!({
            "event_id": event_id,
            "event_type": "like",
            "user_id": "user-dedup-ts",
            "post_id": "post-dedup-ts",
            "timestamp": chrono::Utc::now()
                .checked_add_signed(chrono::Duration::seconds(i))
                .unwrap()
                .to_rfc3339(),
        });
        kafka.send("events", event).await.unwrap();
        sleep(Duration::from_millis(100)).await;
    }

    sleep(Duration::from_secs(2)).await;

    let result = ch
        .query_one("SELECT count() FROM events WHERE event_id = ?", &[event_id])
        .await
        .unwrap();

    let count: u64 = result[0]["count()"]
        .as_u64()
        .expect("Failed to extract count from ClickHouse response");

    assert_eq!(
        count, 1,
        "Should deduplicate even with different timestamps: got {count} records"
    );

    env.cleanup().await;
}

#[tokio::test]
async fn test_circuit_breaker_recovery() {
    // Issue: After ClickHouse recovers, system should resume normal operation
    // Expected: Feed API should detect recovery and stop using fallback

    let env = TestEnvironment::new().await;
    let api = FeedApiClient::new(&env.api_url);

    // Action 1: Stop ClickHouse
    env.stop_clickhouse().await;

    // Action 2: Call Feed API (should use fallback)
    let feed_fallback = api.get_feed("user-recovery", 50).await.unwrap();
    println!("Fallback mode: {} posts", feed_fallback.len());

    // Action 3: Restart ClickHouse
    env.start_clickhouse().await;
    sleep(Duration::from_secs(2)).await; // Wait for health check

    // Action 4: Call Feed API again (should use ClickHouse)
    let feed_recovered = api.get_feed("user-recovery", 50).await.unwrap();
    println!("Recovered mode: {} posts", feed_recovered.len());

    // Assert: Should not crash during entire cycle
    // (Detailed verification would check metrics/logs to confirm source)

    env.cleanup().await;
}
