//! Core Flow Integration Tests
//!
//! Purpose: Verify the complete data flow from event generation to feed API
//! Dependencies: PostgreSQL + Kafka + ClickHouse + Redis (via docker-compose)
//!
//! Test Coverage:
//! 1. CDC consumer reads PostgreSQL changes from Kafka
//! 2. Events consumer reads client events from Kafka
//! 3. ClickHouse receives and stores correct data
//! 4. Feed API returns sorted posts
//! 5. Redis cache works effectively
//!
//! Run: cargo test --test core_flow_test
//! Expected Duration: ~30s per test

use serde_json::json;
use tokio::time::{sleep, Duration, Instant};

mod test_harness;
use test_harness::{
    ClickHouseClient, EventRow, FeedApiClient, KafkaProducer, PostgresClient, RedisClient,
    TestEnvironment,
};

#[tokio::test]
async fn test_cdc_consumption_from_kafka() {
    // Setup: Start infrastructure
    let env = TestEnvironment::new().await;
    let pg = PostgresClient::new(&env.pg_url).await;
    let ch = ClickHouseClient::new(&env.ch_url).await;

    // Action: Insert a post in PostgreSQL
    let post_id = "test-post-001";
    pg.execute_simple(
        "INSERT INTO posts (id, author_id, content, created_at)
         VALUES ($1, $2, $3, NOW())",
        &[&post_id, &"author-123", &"Test post content"],
    )
    .await
    .expect("Failed to insert post into PostgreSQL");

    // Wait for CDC to propagate (Debezium delay + Kafka + Consumer lag)
    sleep(Duration::from_secs(2)).await;

    // Assert: ClickHouse should have the post
    let count: u64 = ch
        .query_one("SELECT count() FROM posts WHERE id = ?", &[post_id])
        .await
        .expect("Failed to query ClickHouse");

    assert_eq!(
        count, 1,
        "CDC should propagate post to ClickHouse: got count={}",
        count
    );

    // Cleanup
    env.cleanup().await;
}

#[tokio::test]
async fn test_events_consumption_from_kafka() {
    let env = TestEnvironment::new().await;
    let kafka = KafkaProducer::new(&env.kafka_brokers).await;
    let ch = ClickHouseClient::new(&env.ch_url).await;

    // Action: Send an event to Kafka
    let event_id = "evt-like-001";
    let event_payload = json!({
        "event_id": event_id,
        "event_type": "like",
        "user_id": "user-456",
        "post_id": "post-789",
        "timestamp": chrono::Utc::now().to_rfc3339(),
    });

    kafka
        .send("events", event_payload)
        .await
        .expect("Failed to send event to Kafka");

    // Wait for consumer to process
    sleep(Duration::from_secs(2)).await;

    // Assert: ClickHouse should have the event
    let count: u64 = ch
        .query_one("SELECT count() FROM events WHERE event_id = ?", &[event_id])
        .await
        .expect("Failed to query ClickHouse");

    assert_eq!(
        count, 1,
        "Events consumer should process event: got count={}",
        count
    );

    env.cleanup().await;
}

#[tokio::test]
async fn test_clickhouse_data_correctness() {
    let env = TestEnvironment::new().await;
    let kafka = KafkaProducer::new(&env.kafka_brokers).await;
    let ch = ClickHouseClient::new(&env.ch_url).await;

    // Action: Send a like event with specific data
    let event_payload = json!({
        "event_id": "evt-correctness-001",
        "event_type": "like",
        "user_id": "user-correctness",
        "post_id": "post-correctness",
        "timestamp": "2025-10-18T10:00:00Z",
    });

    kafka.send("events", event_payload.clone()).await.unwrap();
    sleep(Duration::from_secs(2)).await;

    // Assert: Data fields should match exactly
    let row: EventRow = ch
        .query_one(
            "SELECT event_type, user_id, post_id FROM events WHERE event_id = ?",
            &["evt-correctness-001"],
        )
        .await
        .expect("Failed to query event");

    assert_eq!(row.event_type, "like", "Event type mismatch");
    assert_eq!(row.user_id, "user-correctness", "User ID mismatch");
    assert_eq!(row.post_id, "post-correctness", "Post ID mismatch");

    env.cleanup().await;
}

#[tokio::test]
async fn test_feed_api_returns_sorted_posts() {
    let env = TestEnvironment::new().await;
    let ch = ClickHouseClient::new(&env.ch_url).await;
    let api = FeedApiClient::new(&env.api_url);

    // Setup: Insert posts with different scores
    ch.execute_batch(&[
        "INSERT INTO feed_materialized (user_id, post_id, score, rank) VALUES ('user-feed', 'post-a', 100.0, 1)",
        "INSERT INTO feed_materialized (user_id, post_id, score, rank) VALUES ('user-feed', 'post-b', 200.0, 2)",
        "INSERT INTO feed_materialized (user_id, post_id, score, rank) VALUES ('user-feed', 'post-c', 50.0, 3)",
    ]).await.expect("Failed to insert feed data");

    // Action: Call Feed API
    let feed = api
        .get_feed("user-feed", 50)
        .await
        .expect("Feed API should return successfully");

    // Assert: Posts should be sorted by score descending
    assert_eq!(feed.len(), 3, "Feed should contain 3 posts");
    assert_eq!(
        feed[0].post_id, "post-b",
        "Highest score post should be first"
    );
    assert_eq!(
        feed[1].post_id, "post-a",
        "Second highest score post should be second"
    );
    assert_eq!(
        feed[2].post_id, "post-c",
        "Lowest score post should be last"
    );

    assert!(
        feed[0].score > feed[1].score,
        "Feed should be sorted descending"
    );
    assert!(
        feed[1].score > feed[2].score,
        "Feed should be sorted descending"
    );

    env.cleanup().await;
}

#[tokio::test]
async fn test_redis_cache_effectiveness() {
    let env = TestEnvironment::new().await;
    let redis = RedisClient::new(&env.redis_url).await;
    let api = FeedApiClient::new(&env.api_url);

    // Setup: Pre-populate cache
    let cached_feed = json!([
        {"post_id": "cached-001", "score": 100.0},
        {"post_id": "cached-002", "score": 90.0},
    ]);
    redis
        .set("feed:user-cache:v1", cached_feed.to_string(), 300)
        .await
        .expect("Failed to set Redis cache");

    // Action: Call Feed API (should hit cache)
    let start = Instant::now();
    let feed = api.get_feed("user-cache", 50).await.unwrap();
    let latency = start.elapsed();

    // Assert: Response should be fast (< 50ms for cache hit)
    assert!(
        latency < Duration::from_millis(50),
        "Cache hit should be fast: got {:?}",
        latency
    );

    assert_eq!(feed[0].post_id, "cached-001", "Should return cached data");

    // Action: Invalidate cache and call again
    redis.del("feed:user-cache:v1").await.unwrap();
    let start = Instant::now();
    let _feed = api.get_feed("user-cache", 50).await.unwrap();
    let latency_no_cache = start.elapsed();

    // Assert: Without cache should be slower (> 50ms for ClickHouse query)
    assert!(
        latency_no_cache > Duration::from_millis(50),
        "Without cache should be slower: got {:?}",
        latency_no_cache
    );

    env.cleanup().await;
}

#[tokio::test]
async fn test_complete_event_to_feed_flow() {
    // This is the "golden path" test: everything working together
    let env = TestEnvironment::new().await;
    let pg = PostgresClient::new(&env.pg_url).await;
    let kafka = KafkaProducer::new(&env.kafka_brokers).await;
    let api = FeedApiClient::new(&env.api_url);

    // Step 1: Create a post in PostgreSQL
    let post_id = "golden-post-001";
    pg.execute_simple(
        "INSERT INTO posts (id, author_id, content, created_at) VALUES ($1, $2, $3, NOW())",
        &[&post_id, &"author-golden", &"Golden path test post"],
    )
    .await
    .unwrap();

    // Step 2: Send like events to Kafka
    for i in 0..10 {
        let event = json!({
            "event_id": format!("evt-golden-{:03}", i),
            "event_type": "like",
            "user_id": format!("user-{}", i),
            "post_id": post_id,
            "timestamp": chrono::Utc::now().to_rfc3339(),
        });
        kafka.send("events", event).await.unwrap();
    }

    // Step 3: Wait for CDC + events processing + feed materialization
    sleep(Duration::from_secs(5)).await;

    // Step 4: Call Feed API for a user who follows author-golden
    let feed = api
        .get_feed("user-follower", 50)
        .await
        .expect("Feed API should return successfully");

    // Step 5: Verify the golden post appears in feed with high score
    let golden_post = feed
        .iter()
        .find(|p| p.post_id == post_id)
        .expect("Golden post should appear in feed");

    assert!(
        golden_post.score > 0.0,
        "Post should have positive score from likes"
    );

    env.cleanup().await;
}
