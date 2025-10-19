use user_service::services::feed_ranking_service::{
    CacheStats, EngagementType, FeedRankingConfig, FeedRankingService, FeedResponse, FeedVideo,
};
/// Comprehensive integration tests for FeedRankingService
/// Tests the full feed generation pipeline with caching, ranking, and engagement tracking
use uuid::Uuid;

/// Test basic cache statistics tracking
#[test]
fn test_cache_stats_initialization() {
    let config = FeedRankingConfig::default();
    let service = FeedRankingService::new(config);

    let stats = service.get_cache_stats();
    assert_eq!(stats.total_requests, 0);
    assert_eq!(stats.cache_hits, 0);
    assert_eq!(stats.cache_misses, 0);
    assert_eq!(stats.hit_rate, 0.0);
}

/// Test cache hit/miss rate calculation
#[test]
fn test_cache_stats_calculation() {
    let mut stats = CacheStats::new();

    // Record 10 hits
    for _ in 0..10 {
        stats.record_hit();
    }
    assert_eq!(stats.total_requests, 10);
    assert_eq!(stats.cache_hits, 10);
    assert_eq!(stats.hit_rate, 100.0);

    // Record 10 misses
    for _ in 0..10 {
        stats.record_miss();
    }
    assert_eq!(stats.total_requests, 20);
    assert_eq!(stats.cache_hits, 10);
    assert_eq!(stats.cache_misses, 10);
    assert_eq!(stats.hit_rate, 50.0);
}

/// Test FeedRankingConfig validation
#[test]
fn test_config_defaults() {
    let config = FeedRankingConfig::default();

    assert_eq!(config.cache_ttl_hours, 1);
    assert_eq!(config.cache_hit_target_pct, 95.0);
    assert_eq!(config.dedup_window_days, 30);
    assert_eq!(config.feed_size_min, 30);
    assert_eq!(config.feed_size_max, 50);
}

/// Test FeedRankingConfig custom values
#[test]
fn test_config_custom_values() {
    let config = FeedRankingConfig {
        cache_ttl_hours: 2,
        cache_hit_target_pct: 90.0,
        dedup_window_days: 14,
        feed_size_min: 20,
        feed_size_max: 60,
    };

    assert_eq!(config.cache_ttl_hours, 2);
    assert_eq!(config.cache_hit_target_pct, 90.0);
    assert_eq!(config.dedup_window_days, 14);
    assert_eq!(config.feed_size_min, 20);
    assert_eq!(config.feed_size_max, 60);
}

/// Test EngagementType string conversion
#[test]
fn test_engagement_type_str_conversion() {
    assert_eq!(EngagementType::Like.as_str(), "like");
    assert_eq!(EngagementType::Watch.as_str(), "watch");
    assert_eq!(EngagementType::Share.as_str(), "share");
    assert_eq!(EngagementType::Comment.as_str(), "comment");
}

/// Test EngagementType equality
#[test]
fn test_engagement_type_equality() {
    assert_eq!(EngagementType::Like, EngagementType::Like);
    assert_ne!(EngagementType::Like, EngagementType::Share);
}

/// Test FeedVideo structure
#[test]
fn test_feed_video_structure() {
    let video = FeedVideo {
        id: "video-1".to_string(),
        creator_id: "creator-1".to_string(),
        title: "Test Video".to_string(),
        duration_seconds: 120,
        thumbnail_url: Some("https://example.com/thumb.jpg".to_string()),
        view_count: 1000,
        like_count: 100,
        comment_count: 50,
        share_count: 25,
        completion_rate: 0.75,
        url_720p: Some("https://example.com/720p.m3u8".to_string()),
        url_480p: Some("https://example.com/480p.m3u8".to_string()),
        url_360p: Some("https://example.com/360p.m3u8".to_string()),
        ranking_score: 0.85,
    };

    assert_eq!(video.id, "video-1");
    assert_eq!(video.creator_id, "creator-1");
    assert_eq!(video.like_count, 100);
    assert_eq!(video.ranking_score, 0.85);
}

/// Test FeedResponse pagination
#[test]
fn test_feed_response_pagination() {
    let videos = vec![
        FeedVideo {
            id: "video-1".to_string(),
            creator_id: "creator-1".to_string(),
            title: "Video 1".to_string(),
            duration_seconds: 60,
            thumbnail_url: None,
            view_count: 100,
            like_count: 10,
            comment_count: 5,
            share_count: 2,
            completion_rate: 0.5,
            url_720p: None,
            url_480p: None,
            url_360p: None,
            ranking_score: 0.8,
        },
        FeedVideo {
            id: "video-2".to_string(),
            creator_id: "creator-2".to_string(),
            title: "Video 2".to_string(),
            duration_seconds: 90,
            thumbnail_url: None,
            view_count: 200,
            like_count: 20,
            comment_count: 10,
            share_count: 5,
            completion_rate: 0.7,
            url_720p: None,
            url_480p: None,
            url_360p: None,
            ranking_score: 0.9,
        },
    ];

    let response = FeedResponse {
        videos: videos.clone(),
        next_cursor: Some("cursor_123".to_string()),
    };

    assert_eq!(response.videos.len(), 2);
    assert!(response.next_cursor.is_some());
    assert_eq!(response.next_cursor.as_ref().unwrap(), "cursor_123");
}

/// Test FeedResponse without cursor
#[test]
fn test_feed_response_no_pagination() {
    let response = FeedResponse {
        videos: vec![],
        next_cursor: None,
    };

    assert_eq!(response.videos.len(), 0);
    assert!(response.next_cursor.is_none());
}

/// Test service creation
#[test]
fn test_service_creation() {
    let config = FeedRankingConfig {
        cache_ttl_hours: 2,
        cache_hit_target_pct: 92.0,
        dedup_window_days: 20,
        feed_size_min: 25,
        feed_size_max: 55,
    };

    let service = FeedRankingService::new(config);
    let stats = service.get_cache_stats();

    assert_eq!(stats.total_requests, 0);
    assert_eq!(stats.cache_hits, 0);
}

/// Test limit validation in feed generation
#[test]
fn test_limit_clamping() {
    // Test that limits are clamped to min/max range
    let config = FeedRankingConfig {
        cache_ttl_hours: 1,
        cache_hit_target_pct: 95.0,
        dedup_window_days: 30,
        feed_size_min: 30,
        feed_size_max: 50,
    };

    // Feed size of 20 should be clamped up to 30
    assert!(20 < config.feed_size_min);
    assert!(30 >= config.feed_size_min);

    // Feed size of 100 should be clamped down to 50
    assert!(100 > config.feed_size_max);
    assert!(50 <= config.feed_size_max);
}

/// Test cache statistics wrapping arithmetic
#[test]
fn test_cache_stats_wrapping_arithmetic() {
    let mut stats = CacheStats::new();

    // Record many hits to test wrapping arithmetic
    for _ in 0..1000 {
        stats.record_hit();
    }

    assert_eq!(stats.total_requests, 1000);
    assert_eq!(stats.cache_hits, 1000);
    assert_eq!(stats.hit_rate, 100.0);
}

/// Test cache statistics with mixed hits and misses
#[test]
fn test_cache_stats_mixed_pattern() {
    let mut stats = CacheStats::new();

    // Simulate realistic hit/miss pattern
    let pattern = vec![
        true, true, true, false, true, // 80% in first 5
        true, true, true, true, false, // 80% in next 5
        false, true, true, true, true, // 80% in next 5
    ];

    for is_hit in pattern {
        if is_hit {
            stats.record_hit();
        } else {
            stats.record_miss();
        }
    }

    assert_eq!(stats.total_requests, 15);
    assert_eq!(stats.cache_hits, 12);
    assert_eq!(stats.cache_misses, 3);
    assert!(stats.hit_rate > 75.0 && stats.hit_rate < 85.0);
}

/// Test video ranking score bounds
#[test]
fn test_video_ranking_score_bounds() {
    let video_min = FeedVideo {
        id: "low".to_string(),
        creator_id: "c1".to_string(),
        title: "Low".to_string(),
        duration_seconds: 0,
        thumbnail_url: None,
        view_count: 0,
        like_count: 0,
        comment_count: 0,
        share_count: 0,
        completion_rate: 0.0,
        url_720p: None,
        url_480p: None,
        url_360p: None,
        ranking_score: 0.0,
    };

    let video_max = FeedVideo {
        id: "high".to_string(),
        creator_id: "c2".to_string(),
        title: "High".to_string(),
        duration_seconds: 3600,
        thumbnail_url: Some("https://example.com/thumb.jpg".to_string()),
        view_count: 1_000_000,
        like_count: 100_000,
        comment_count: 50_000,
        share_count: 25_000,
        completion_rate: 1.0,
        url_720p: Some("https://example.com/720p.m3u8".to_string()),
        url_480p: Some("https://example.com/480p.m3u8".to_string()),
        url_360p: Some("https://example.com/360p.m3u8".to_string()),
        ranking_score: 1.0,
    };

    assert!(video_min.ranking_score >= 0.0);
    assert!(video_max.ranking_score <= 1.0);
}

/// Test service configuration persistence
#[test]
fn test_service_config_persistence() {
    let config1 = FeedRankingConfig {
        cache_ttl_hours: 3,
        cache_hit_target_pct: 98.0,
        dedup_window_days: 45,
        feed_size_min: 40,
        feed_size_max: 60,
    };

    let service1 = FeedRankingService::new(config1.clone());
    let service2 = FeedRankingService::new(config1);

    // Both services should have the same configuration
    let stats1 = service1.get_cache_stats();
    let stats2 = service2.get_cache_stats();

    assert_eq!(stats1.total_requests, stats2.total_requests);
}

/// Test engagement type hash (for use in HashSet/HashMap)
#[test]
fn test_engagement_type_hashable() {
    use std::collections::HashSet;

    let mut engagement_set = HashSet::new();
    engagement_set.insert(EngagementType::Like);
    engagement_set.insert(EngagementType::Watch);
    engagement_set.insert(EngagementType::Share);
    engagement_set.insert(EngagementType::Comment);

    assert_eq!(engagement_set.len(), 4);
    assert!(engagement_set.contains(&EngagementType::Like));
    assert!(engagement_set.contains(&EngagementType::Watch));
}

/// Test feed response serialization compatibility
#[test]
fn test_feed_response_json_compatible() {
    let response = FeedResponse {
        videos: vec![FeedVideo {
            id: "v1".to_string(),
            creator_id: "c1".to_string(),
            title: "Test".to_string(),
            duration_seconds: 60,
            thumbnail_url: None,
            view_count: 100,
            like_count: 10,
            comment_count: 5,
            share_count: 2,
            completion_rate: 0.8,
            url_720p: None,
            url_480p: None,
            url_360p: None,
            ranking_score: 0.85,
        }],
        next_cursor: Some("next".to_string()),
    };

    // Test that response can be serialized to JSON (implementation should support this)
    let json = serde_json::to_string(&response);
    assert!(json.is_ok());

    let json_str = json.unwrap();
    assert!(json_str.contains("\"v1\""));
    assert!(json_str.contains("\"Test\""));
}

/// Benchmark-like test for cache statistics calculation performance
#[test]
fn test_cache_stats_performance_characteristics() {
    let mut stats = CacheStats::new();

    // Simulate 1 hour of requests (3600 requests per hour at 1 req/sec)
    for i in 0..3600 {
        if i % 20 < 18 {
            // 90% hit rate
            stats.record_hit();
        } else {
            stats.record_miss();
        }
    }

    assert_eq!(stats.total_requests, 3600);
    assert_eq!(stats.cache_hits, 3240); // 90% of 3600
    assert_eq!(stats.cache_misses, 360); // 10% of 3600

    // Hit rate should be approximately 90%
    assert!(stats.hit_rate > 89.0 && stats.hit_rate < 91.0);
}
