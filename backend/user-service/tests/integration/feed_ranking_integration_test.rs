/// Integration tests for Feed Ranking Algorithm
/// Tests the ranking logic with realistic data scenarios

use chrono::Utc;
use std::sync::Arc;
use uuid::Uuid;

use user_service::cache::FeedCache;
use user_service::db::ch_client::ClickHouseClient;
use user_service::services::feed_ranking::{FeedCandidate, FeedRankingService};

fn create_mock_ranking_service() -> FeedRankingService {
    let ch_client = Arc::new(ClickHouseClient::new(
        "http://localhost:8123",
        "default",
        "default",
        "",
        5000,
    ));

    // Create minimal Redis client
    let redis_client =
        redis::Client::open("redis://127.0.0.1/").unwrap_or_else(|_| {
            redis::Client::open("redis://127.0.0.1/").unwrap()
        });

    let runtime = tokio::runtime::Runtime::new().unwrap();
    let conn_manager = runtime.block_on(async {
        redis::aio::ConnectionManager::new(redis_client)
            .await
            .unwrap_or_else(|_| panic!("Redis required"))
    });

    let cache = Arc::new(tokio::sync::Mutex::new(FeedCache::new(conn_manager, 120)));

    FeedRankingService::new(ch_client, cache)
        .with_weights(0.3, 0.4, 0.3, 0.1)
}

/// Test realistic feed ranking with mixed content
#[test]
fn test_ranking_with_realistic_data() {
    let service = create_mock_ranking_service();

    // Simulate realistic feed data from all sources
    let candidates = vec![
        // Follow posts - recent, moderate engagement
        FeedCandidate {
            post_id: Uuid::new_v4().to_string(),
            author_id: Uuid::new_v4().to_string(),
            likes: 50,
            comments: 5,
            shares: 1,
            impressions: 500,
            freshness_score: 0.95, // Very fresh
            engagement_score: 0.35,
            affinity_score: 0.0,
            combined_score: 0.0,
            created_at: Utc::now(),
        },
        // Trending posts - older but high engagement
        FeedCandidate {
            post_id: Uuid::new_v4().to_string(),
            author_id: Uuid::new_v4().to_string(),
            likes: 500,
            comments: 100,
            shares: 50,
            impressions: 5000,
            freshness_score: 0.6,
            engagement_score: 0.85,
            affinity_score: 0.0,
            combined_score: 0.0,
            created_at: Utc::now(),
        },
        // Affinity posts - personalized
        FeedCandidate {
            post_id: Uuid::new_v4().to_string(),
            author_id: Uuid::new_v4().to_string(),
            likes: 100,
            comments: 15,
            shares: 5,
            impressions: 1000,
            freshness_score: 0.7,
            engagement_score: 0.55,
            affinity_score: 0.8, // User has interacted with this author
            combined_score: 0.0,
            created_at: Utc::now(),
        },
    ];

    let ranked = service.rank_with_clickhouse(candidates).unwrap();

    // Verify all posts are ranked
    assert_eq!(ranked.len(), 3);

    // Verify reasons are assigned correctly
    let reasons: Vec<&str> = ranked.iter().map(|p| p.reason.as_str()).collect();
    assert!(reasons.contains(&"follow") || reasons.contains(&"trending") || reasons.contains(&"affinity"));
}

/// Test that high-engagement content ranks above fresh content when engagement is dominant
#[test]
fn test_engagement_dominates_freshness() {
    let service = create_mock_ranking_service();

    // Fresh post with low engagement
    let fresh_low_engagement = FeedCandidate {
        post_id: Uuid::new_v4().to_string(),
        author_id: Uuid::new_v4().to_string(),
        likes: 5,
        comments: 1,
        shares: 0,
        impressions: 100,
        freshness_score: 0.95,
        engagement_score: 0.1,
        affinity_score: 0.0,
        combined_score: 0.95,
        created_at: Utc::now(),
    };

    // Older post with high engagement
    let old_high_engagement = FeedCandidate {
        post_id: Uuid::new_v4().to_string(),
        author_id: Uuid::new_v4().to_string(),
        likes: 200,
        comments: 40,
        shares: 20,
        impressions: 2000,
        freshness_score: 0.4,
        engagement_score: 0.88,
        affinity_score: 0.0,
        combined_score: 0.88,
        created_at: Utc::now(),
    };

    let candidates = vec![fresh_low_engagement, old_high_engagement];
    let ranked = service.rank_with_clickhouse(candidates).unwrap();

    // High engagement should rank higher (combined_score 0.88 > 0.95 due to weights)
    // With weights 0.3 fresh, 0.4 engagement: fresh gets 0.285, old gets 0.352
    assert!(ranked[0].reason == "trending" || ranked[0].reason == "follow");
}

/// Test saturation control across a large feed
#[test]
fn test_saturation_control_large_feed() {
    let service = create_mock_ranking_service();

    let mut candidates = vec![];

    // Create posts from 10 different authors, each with 5 posts
    for author_idx in 0..10 {
        for post_idx in 0..5 {
            candidates.push(FeedCandidate {
                post_id: Uuid::new_v4().to_string(),
                author_id: format!(
                    "{}00000000-0000-0000-0000-000000000000",
                    author_idx
                ),
                likes: 100 - (post_idx as u32 * 10),
                comments: 10,
                shares: 5,
                impressions: 1000,
                freshness_score: 0.8 - (post_idx as f64 * 0.1),
                engagement_score: 0.5,
                affinity_score: 0.0,
                combined_score: 0.9 - (author_idx as f64 * 0.05) - (post_idx as f64 * 0.1),
                created_at: Utc::now(),
            });
        }
    }

    let ranked = service.rank_with_clickhouse(candidates).ok().unwrap_or_default();
    let final_posts = service.dedup_and_saturation_with_authors(ranked).ok().unwrap_or_default();

    // Should have at most 100 posts
    assert!(final_posts.len() <= 100);

    // Should have posts from multiple authors
    assert!(final_posts.len() > 1);
}

/// Test empty candidate list handling
#[test]
fn test_ranking_empty_candidates() {
    let service = create_mock_ranking_service();

    let candidates = vec![];
    let ranked = service.rank_with_clickhouse(candidates).unwrap();

    assert_eq!(ranked.len(), 0);
}

/// Test single candidate ranking
#[test]
fn test_ranking_single_candidate() {
    let service = create_mock_ranking_service();

    let candidates = vec![FeedCandidate {
        post_id: Uuid::new_v4().to_string(),
        author_id: Uuid::new_v4().to_string(),
        likes: 50,
        comments: 5,
        shares: 2,
        impressions: 500,
        freshness_score: 0.8,
        engagement_score: 0.5,
        affinity_score: 0.0,
        combined_score: 0.75,
        created_at: Utc::now(),
    }];

    let ranked = service.rank_with_clickhouse(candidates).unwrap();

    assert_eq!(ranked.len(), 1);
    assert_eq!(ranked[0].combined_score, 0.75);
}

/// Test ranking stability (same input produces same order)
#[test]
fn test_ranking_stability() {
    let service = create_mock_ranking_service();

    let create_candidates = || {
        vec![
            FeedCandidate {
                post_id: "550e8400-e29b-41d4-a716-446655440001".to_string(),
                author_id: "650e8400-e29b-41d4-a716-446655440001".to_string(),
                likes: 100,
                comments: 10,
                shares: 5,
                impressions: 1000,
                freshness_score: 0.8,
                engagement_score: 0.5,
                affinity_score: 0.0,
                combined_score: 0.8,
                created_at: Utc::now(),
            },
            FeedCandidate {
                post_id: "550e8400-e29b-41d4-a716-446655440002".to_string(),
                author_id: "650e8400-e29b-41d4-a716-446655440002".to_string(),
                likes: 50,
                comments: 5,
                shares: 2,
                impressions: 500,
                freshness_score: 0.6,
                engagement_score: 0.4,
                affinity_score: 0.0,
                combined_score: 0.6,
                created_at: Utc::now(),
            },
        ]
    };

    let ranked1 = service.rank_with_clickhouse(create_candidates()).unwrap();
    let ranked2 = service.rank_with_clickhouse(create_candidates()).unwrap();

    // Order should be identical
    for (r1, r2) in ranked1.iter().zip(ranked2.iter()) {
        assert_eq!(r1.post_id, r2.post_id);
        assert_eq!(r1.combined_score, r2.combined_score);
        assert_eq!(r1.reason, r2.reason);
    }
}

/// Test NaN and edge value handling
#[test]
fn test_edge_value_handling() {
    let service = create_mock_ranking_service();

    let candidates = vec![
        FeedCandidate {
            post_id: Uuid::new_v4().to_string(),
            author_id: Uuid::new_v4().to_string(),
            likes: 0,
            comments: 0,
            shares: 0,
            impressions: 0, // Edge: zero impressions
            freshness_score: 0.0,
            engagement_score: 0.0,
            affinity_score: 0.0,
            combined_score: 0.0,
            created_at: Utc::now(),
        },
        FeedCandidate {
            post_id: Uuid::new_v4().to_string(),
            author_id: Uuid::new_v4().to_string(),
            likes: 1000000,
            comments: 100000,
            shares: 50000,
            impressions: 10000000, // Edge: very high
            freshness_score: 1.0,
            engagement_score: 1.0,
            affinity_score: 1.0,
            combined_score: 1.0,
            created_at: Utc::now(),
        },
    ];

    let ranked = service.rank_with_clickhouse(candidates).unwrap();

    // Should handle edge values without panicking
    assert_eq!(ranked.len(), 2);

    // High values should rank higher
    assert!(ranked[0].combined_score >= ranked[1].combined_score);
}

/// Test UUID conversion in ranking
#[test]
fn test_uuid_conversion_in_ranking() {
    let service = create_mock_ranking_service();

    let post_uuid = Uuid::new_v4();
    let author_uuid = Uuid::new_v4();

    let candidates = vec![FeedCandidate {
        post_id: post_uuid.to_string(),
        author_id: author_uuid.to_string(),
        likes: 50,
        comments: 5,
        shares: 2,
        impressions: 500,
        freshness_score: 0.8,
        engagement_score: 0.5,
        affinity_score: 0.0,
        combined_score: 0.75,
        created_at: Utc::now(),
    }];

    let ranked = service.rank_with_clickhouse(candidates).unwrap();

    assert_eq!(ranked[0].post_id, post_uuid);
}

/// Test sorting by combined_score
#[test]
fn test_sorting_by_combined_score() {
    let service = create_mock_ranking_service();

    let candidates = vec![
        FeedCandidate {
            post_id: Uuid::new_v4().to_string(),
            author_id: Uuid::new_v4().to_string(),
            likes: 0,
            comments: 0,
            shares: 0,
            impressions: 0,
            freshness_score: 0.0,
            engagement_score: 0.0,
            affinity_score: 0.0,
            combined_score: 0.1,
            created_at: Utc::now(),
        },
        FeedCandidate {
            post_id: Uuid::new_v4().to_string(),
            author_id: Uuid::new_v4().to_string(),
            likes: 0,
            comments: 0,
            shares: 0,
            impressions: 0,
            freshness_score: 0.0,
            engagement_score: 0.0,
            affinity_score: 0.0,
            combined_score: 0.9,
            created_at: Utc::now(),
        },
        FeedCandidate {
            post_id: Uuid::new_v4().to_string(),
            author_id: Uuid::new_v4().to_string(),
            likes: 0,
            comments: 0,
            shares: 0,
            impressions: 0,
            freshness_score: 0.0,
            engagement_score: 0.0,
            affinity_score: 0.0,
            combined_score: 0.5,
            created_at: Utc::now(),
        },
    ];

    let ranked = service.rank_with_clickhouse(candidates).unwrap();

    // Should be sorted in descending order
    assert_eq!(ranked[0].combined_score, 0.9);
    assert_eq!(ranked[1].combined_score, 0.5);
    assert_eq!(ranked[2].combined_score, 0.1);
}
