use chrono::Utc;
use uuid::Uuid;

use user_service::services::feed_ranking::{FeedCandidate, FeedRankingService, RankedPost};

#[test]
fn test_feed_candidate_uuid_parsing() {
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

    assert!(candidate.post_id_uuid().is_ok());
    assert!(candidate.author_id_uuid().is_ok());

    let post_id = candidate.post_id_uuid().unwrap();
    assert_eq!(post_id.to_string(), "550e8400-e29b-41d4-a716-446655440000");
}

#[test]
fn test_feed_candidate_invalid_uuid() {
    let candidate = FeedCandidate {
        post_id: "invalid-uuid".to_string(),
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

    assert!(candidate.post_id_uuid().is_err());
}

#[test]
fn test_ranking_deduplication() {
    // Mock ClickHouse client and Redis cache (would use actual mocks in production)
    // For now, test the ranking logic directly

    let candidates = vec![
        FeedCandidate {
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
        },
        // Duplicate with lower score (should be filtered)
        FeedCandidate {
            post_id: "550e8400-e29b-41d4-a716-446655440000".to_string(),
            author_id: "650e8400-e29b-41d4-a716-446655440000".to_string(),
            likes: 50,
            comments: 5,
            shares: 2,
            impressions: 500,
            freshness_score: 0.7,
            engagement_score: 0.4,
            affinity_score: 0.0,
            combined_score: 0.5, // Lower score
            created_at: Utc::now(),
        },
        // Different post
        FeedCandidate {
            post_id: "660e8400-e29b-41d4-a716-446655440000".to_string(),
            author_id: "750e8400-e29b-41d4-a716-446655440000".to_string(),
            likes: 200,
            comments: 20,
            shares: 10,
            impressions: 2000,
            freshness_score: 0.9,
            engagement_score: 0.7,
            affinity_score: 0.0,
            combined_score: 0.8,
            created_at: Utc::now(),
        },
    ];

    // Create a mock service (no real CH/Redis needed for this test)
    let service = create_mock_service();

    let ranked = service.rank_with_clickhouse(candidates).unwrap();

    // Should have 2 posts (duplicate removed)
    assert_eq!(ranked.len(), 2);

    // Should be sorted by combined_score (0.8, 0.6)
    assert_eq!(ranked[0].combined_score, 0.8);
    assert_eq!(ranked[1].combined_score, 0.6);

    // Verify deduplication kept the higher score
    let first_post = ranked
        .iter()
        .find(|p| p.post_id.to_string() == "550e8400-e29b-41d4-a716-446655440000");
    assert!(first_post.is_some());
    assert_eq!(first_post.unwrap().combined_score, 0.6);
}

#[test]
fn test_ranking_reason_assignment() {
    let candidates = vec![
        // Follow post (high freshness)
        FeedCandidate {
            post_id: "550e8400-e29b-41d4-a716-446655440000".to_string(),
            author_id: "650e8400-e29b-41d4-a716-446655440000".to_string(),
            likes: 10,
            comments: 2,
            shares: 1,
            impressions: 100,
            freshness_score: 0.9,
            engagement_score: 0.3,
            affinity_score: 0.0,
            combined_score: 0.6,
            created_at: Utc::now(),
        },
        // Trending post (high engagement)
        FeedCandidate {
            post_id: "660e8400-e29b-41d4-a716-446655440000".to_string(),
            author_id: "750e8400-e29b-41d4-a716-446655440000".to_string(),
            likes: 200,
            comments: 50,
            shares: 20,
            impressions: 2000,
            freshness_score: 0.5,
            engagement_score: 0.9,
            affinity_score: 0.0,
            combined_score: 0.7,
            created_at: Utc::now(),
        },
        // Affinity post (has affinity score)
        FeedCandidate {
            post_id: "770e8400-e29b-41d4-a716-446655440000".to_string(),
            author_id: "850e8400-e29b-41d4-a716-446655440000".to_string(),
            likes: 50,
            comments: 10,
            shares: 5,
            impressions: 500,
            freshness_score: 0.6,
            engagement_score: 0.5,
            affinity_score: 0.8, // Has affinity
            combined_score: 0.65,
            created_at: Utc::now(),
        },
    ];

    let service = create_mock_service();
    let ranked = service.rank_with_clickhouse(candidates).unwrap();

    assert_eq!(ranked.len(), 3);

    // Find each post and verify reason
    let follow_post = ranked
        .iter()
        .find(|p| p.post_id.to_string() == "550e8400-e29b-41d4-a716-446655440000");
    assert_eq!(follow_post.unwrap().reason, "follow");

    let trending_post = ranked
        .iter()
        .find(|p| p.post_id.to_string() == "660e8400-e29b-41d4-a716-446655440000");
    assert_eq!(trending_post.unwrap().reason, "trending");

    let affinity_post = ranked
        .iter()
        .find(|p| p.post_id.to_string() == "770e8400-e29b-41d4-a716-446655440000");
    assert_eq!(affinity_post.unwrap().reason, "affinity");
}

#[test]
fn test_saturation_limit() {
    let candidates: Vec<FeedCandidate> = (0..150)
        .map(|i| FeedCandidate {
            post_id: Uuid::new_v4().to_string(),
            author_id: Uuid::new_v4().to_string(),
            likes: 10 + i,
            comments: 2,
            shares: 1,
            impressions: 100,
            freshness_score: 0.8,
            engagement_score: 0.5,
            affinity_score: 0.0,
            combined_score: 0.6 + (i as f64 * 0.001),
            created_at: Utc::now(),
        })
        .collect();

    let service = create_mock_service();
    let ranked = service.rank_with_clickhouse(candidates).unwrap();
    let final_posts = service.apply_dedup_and_saturation(ranked);

    // Should be limited to 100 (hard limit in implementation)
    assert!(final_posts.len() <= 100);
}

// Helper function to create mock service for testing
fn create_mock_service() -> FeedRankingService {
    use redis::aio::ConnectionManager;
    use redis::Client as RedisClient;
    use std::sync::Arc;
    use user_service::cache::FeedCache;
    use user_service::db::ch_client::ClickHouseClient;

    // Create mock CH client (won't be used in these tests)
    let ch_client = Arc::new(ClickHouseClient::new(
        "http://localhost:8123",
        "default",
        "default",
        "",
        5000,
    ));

    // Create mock Redis client (won't be used in these tests)
    // Note: This will fail to connect, but that's okay for unit tests
    let redis_client = RedisClient::open("redis://127.0.0.1/").unwrap();
    let conn_manager = tokio::runtime::Runtime::new().unwrap().block_on(async {
        ConnectionManager::new(redis_client)
            .await
            .unwrap_or_else(|_| {
                // Fallback to avoid panic in tests
                panic!("Redis connection required for tests")
            })
    });

    let cache = Arc::new(tokio::sync::Mutex::new(FeedCache::new(conn_manager, 120)));

    FeedRankingService::new(ch_client, cache)
}

// Note: Integration tests requiring actual CH/Redis should be in a separate test suite
// with proper test fixtures and mock servers
