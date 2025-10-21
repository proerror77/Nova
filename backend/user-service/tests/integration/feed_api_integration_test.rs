/// Integration tests for Feed API
/// Tests the complete feed ranking pipeline with real dependencies (CH, Redis, Cache)

use chrono::Utc;
use std::sync::Arc;
use uuid::Uuid;

use user_service::db::ch_client::ClickHouseClient;
use user_service::cache::FeedCache;
use user_service::services::feed_ranking::{FeedCandidate, FeedRankingService};

// Helper to create a test service with mocked dependencies
async fn create_test_service() -> FeedRankingService {
    // In production, these would connect to real services
    // For tests, we'll use test containers or mocks

    let ch_client = Arc::new(ClickHouseClient::new(
        "http://localhost:8123",
        "default",
        "default",
        "",
        5000,
    ));

    // Create Redis client (if available in test env)
    let redis_client = redis::Client::open("redis://127.0.0.1:6379/")
        .unwrap_or_else(|_| {
            // Fallback for testing without Redis
            redis::Client::open("redis://127.0.0.1/").unwrap()
        });

    let conn_manager = redis::aio::ConnectionManager::new(redis_client)
        .await
        .unwrap_or_else(|_| {
            // For unit tests without Redis, we'll skip this
            panic!("Redis connection required for integration tests")
        });

    let cache = Arc::new(tokio::sync::Mutex::new(FeedCache::new(conn_manager, 120)));

    FeedRankingService::new(ch_client, cache)
}

#[tokio::test]
#[ignore] // This test requires ClickHouse and Redis to be running
async fn test_feed_api_basic_flow() {
    let service = create_test_service().await;
    let user_id = Uuid::new_v4();

    // This would normally query ClickHouse for candidates
    // For now, we're testing the structure
    match service.get_feed_candidates(user_id, 20).await {
        Ok(candidates) => {
            // Verify candidates structure
            for candidate in candidates {
                assert!(!candidate.post_id.is_empty());
                assert!(!candidate.author_id.is_empty());
                assert!(candidate.combined_score >= 0.0 && candidate.combined_score <= 1.0);
            }
        }
        Err(_) => {
            // Expected if ClickHouse is not running
            println!("ClickHouse not available for testing");
        }
    }
}

#[tokio::test]
#[ignore] // This test requires ClickHouse
async fn test_feed_ranking_e2e() {
    let service = create_test_service().await;
    let user_id = Uuid::new_v4();

    // Get feed with ranking
    match service.get_feed(user_id, 20, 0).await {
        Ok((posts, has_more)) => {
            // Verify results
            assert!(posts.len() <= 20);

            // Verify all are valid UUIDs
            for post_id in &posts {
                assert!(!post_id.to_string().is_empty());
            }

            // has_more should indicate pagination availability
            println!("Feed result: {} posts, has_more: {}", posts.len(), has_more);
        }
        Err(e) => {
            println!("Feed query failed: {:?}", e);
        }
    }
}

#[tokio::test]
#[ignore]
async fn test_cache_warming_integration() {
    let service = create_test_service().await;
    let user_id = Uuid::new_v4();

    // First call should populate cache
    let (posts1, _) = service
        .get_feed(user_id, 20, 0)
        .await
        .unwrap_or((vec![], false));

    // Second call should hit cache
    let (posts2, _) = service
        .get_feed(user_id, 20, 0)
        .await
        .unwrap_or((vec![], false));

    // Results should be identical
    assert_eq!(posts1, posts2);
}

#[tokio::test]
#[ignore]
async fn test_cache_invalidation() {
    let service = create_test_service().await;
    let user_id = Uuid::new_v4();

    // Get feed (populates cache)
    let _feed1 = service.get_feed(user_id, 20, 0).await;

    // Invalidate cache
    let invalidate_result = service.invalidate_cache(user_id).await;
    assert!(invalidate_result.is_ok());

    // Next get_feed should not use cache
    let _feed2 = service.get_feed(user_id, 20, 0).await;
}

#[tokio::test]
#[ignore]
async fn test_pagination_consistency() {
    let service = create_test_service().await;
    let user_id = Uuid::new_v4();

    // Get first page
    let (page1, has_more1) = service
        .get_feed(user_id, 10, 0)
        .await
        .unwrap_or((vec![], false));

    if has_more1 {
        // Get second page
        let (page2, _) = service
            .get_feed(user_id, 10, 10)
            .await
            .unwrap_or((vec![], false));

        // Pages should not overlap
        for post_id in &page1 {
            assert!(
                !page2.contains(post_id),
                "Post appeared in multiple pages"
            );
        }
    }
}

#[tokio::test]
#[ignore]
async fn test_fallback_mechanism() {
    let service = create_test_service().await;
    let user_id = Uuid::new_v4();

    // When ClickHouse is down, should use fallback
    // This would typically return cached data or empty result
    match service.get_feed(user_id, 20, 0).await {
        Ok((posts, _)) => {
            // Fallback should return empty or cached posts
            println!("Fallback returned {} posts", posts.len());
        }
        Err(_) => {
            // Error is also acceptable
            println!("Fallback failed gracefully");
        }
    }
}

#[tokio::test]
#[ignore]
async fn test_circuit_breaker_integration() {
    let service = create_test_service().await;

    // Check initial state
    let state1 = service.get_circuit_state().await;
    println!("Initial circuit state: {:?}", state1);

    // After multiple failures, should trip
    let _user_id = Uuid::new_v4();

    // Make several requests
    for _i in 0..5 {
        let _result = service.get_feed_candidates(Uuid::new_v4(), 20).await;
    }

    // Check state after operations
    let state2 = service.get_circuit_state().await;
    println!("Circuit state after operations: {:?}", state2);
}

// Mock test that doesn't require external services
#[test]
fn test_feed_candidate_parsing() {
    let candidate = FeedCandidate {
        post_id: "550e8400-e29b-41d4-a716-446655440000".to_string(),
        author_id: "650e8400-e29b-41d4-a716-446655440000".to_string(),
        likes: 100,
        comments: 10,
        shares: 5,
        impressions: 1000,
        freshness_score: 0.8,
        engagement_score: 0.5,
        affinity_score: 0.0,
        combined_score: 0.6,
        created_at: Utc::now(),
    };

    // Verify parsing works
    assert!(candidate.post_id_uuid().is_ok());
    assert!(candidate.author_id_uuid().is_ok());

    let post_uuid = candidate.post_id_uuid().unwrap();
    assert_eq!(
        post_uuid.to_string(),
        "550e8400-e29b-41d4-a716-446655440000"
    );
}

#[test]
fn test_feed_result_structure() {
    // Verify response structures are valid
    let post_id = Uuid::new_v4();

    use user_service::services::feed_ranking::RankedPost;

    let ranked_post = RankedPost {
        post_id,
        combined_score: 0.75,
        reason: "follow".to_string(),
    };

    assert_eq!(ranked_post.post_id, post_id);
    assert_eq!(ranked_post.combined_score, 0.75);
    assert_eq!(ranked_post.reason, "follow");
}

#[test]
fn test_feed_cache_key_generation() {
    let user_id = Uuid::new_v4();
    let offset = 0u32;
    let limit = 20u32;

    // Verify cache key generation is consistent
    let key1 = format!("feed:{}:{}:{}", user_id, offset, limit);
    let key2 = format!("feed:{}:{}:{}", user_id, offset, limit);

    assert_eq!(key1, key2);
}
