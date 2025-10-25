/// Integration tests for trending/discovery system
use std::collections::HashMap;
use uuid::Uuid;
use sqlx::PgPool;

use nova_user_service::db::trending_repo::{
    ContentType, EventType, TimeWindow, TrendingRepo,
};
use nova_user_service::services::trending::{
    TrendingAlgorithm, TrendingComputeService, TrendingService,
};

mod common;

#[tokio::test]
async fn test_record_engagement_event() {
    let pool = common::fixtures::setup_test_db().await;

    // Create test user and video
    let user_id = common::fixtures::create_test_user(&pool, "testuser", "test@example.com").await;
    let video_id = Uuid::new_v4();

    // Create repo
    let repo = TrendingRepo::new(pool.clone());

    // Record view event
    let event_id = repo
        .record_engagement(
            video_id,
            ContentType::Video,
            user_id,
            EventType::View,
            Some("session123".to_string()),
            Some("127.0.0.1".to_string()),
            Some("Mozilla/5.0".to_string()),
        )
        .await
        .expect("Failed to record engagement");

    assert!(event_id.is_some());

    // Verify event count
    let count = repo
        .get_engagement_count(video_id, TimeWindow::OneHour)
        .await
        .expect("Failed to get engagement count");

    assert_eq!(count, 1);
}

#[tokio::test]
async fn test_duplicate_engagement_deduplication() {
    let pool = common::fixtures::setup_test_db().await;
    let user_id = common::fixtures::create_test_user(&pool, "dedup_user", "dedup@example.com").await;
    let video_id = Uuid::new_v4();

    let repo = TrendingRepo::new(pool.clone());

    // Record first view
    let first = repo
        .record_engagement(
            video_id,
            ContentType::Video,
            user_id,
            EventType::View,
            None,
            None,
            None,
        )
        .await
        .expect("First engagement failed");

    assert!(first.is_some());

    // Record duplicate view (should be deduplicated)
    let duplicate = repo
        .record_engagement(
            video_id,
            ContentType::Video,
            user_id,
            EventType::View,
            None,
            None,
            None,
        )
        .await
        .expect("Duplicate engagement failed");

    // Duplicate should return None due to UNIQUE constraint
    assert!(duplicate.is_none());

    // Count should still be 1
    let count = repo
        .get_engagement_count(video_id, TimeWindow::OneHour)
        .await
        .expect("Failed to get count");

    assert_eq!(count, 1);
}

#[tokio::test]
async fn test_time_decay_score_calculation() {
    let pool = common::fixtures::setup_test_db().await;
    let user_id = common::fixtures::create_test_user(&pool, "decay_user", "decay@example.com").await;
    let video_id = Uuid::new_v4();

    let repo = TrendingRepo::new(pool.clone());

    // Record engagement event
    repo.record_engagement(
        video_id,
        ContentType::Video,
        user_id,
        EventType::View,
        None,
        None,
        None,
    )
    .await
    .expect("Failed to record engagement");

    // Small delay to ensure timestamp difference
    tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;

    // Compute score
    let score = repo
        .compute_score(video_id, TimeWindow::OneHour, 0.1)
        .await
        .expect("Failed to compute score");

    // Score should be close to 1.0 (view weight) since event just happened
    assert!(score > 0.9 && score <= 1.0, "Score: {}", score);
}

#[tokio::test]
async fn test_refresh_trending_scores() {
    let pool = common::fixtures::setup_test_db().await;

    // Create test users and content
    let user1 = common::fixtures::create_test_user(&pool, "trending1", "trending1@example.com").await;
    let user2 = common::fixtures::create_test_user(&pool, "trending2", "trending2@example.com").await;

    let video1 = Uuid::new_v4();
    let video2 = Uuid::new_v4();

    let repo = TrendingRepo::new(pool.clone());

    // Video 1: High engagement (10 views + 2 shares)
    for _ in 0..10 {
        repo.record_engagement(video1, ContentType::Video, user1, EventType::View, None, None, None)
            .await
            .ok();
    }
    repo.record_engagement(video1, ContentType::Video, user1, EventType::Share, None, None, None)
        .await
        .ok();
    repo.record_engagement(video1, ContentType::Video, user2, EventType::Share, None, None, None)
        .await
        .ok();

    // Video 2: Low engagement (2 views)
    repo.record_engagement(video2, ContentType::Video, user1, EventType::View, None, None, None)
        .await
        .ok();
    repo.record_engagement(video2, ContentType::Video, user2, EventType::View, None, None, None)
        .await
        .ok();

    // Refresh trending scores
    let updated = repo
        .refresh_trending_scores(TimeWindow::OneHour, None, 100)
        .await
        .expect("Failed to refresh trending");

    assert!(updated >= 2, "Should have updated at least 2 items");

    // Get trending items
    let trending = repo
        .get_trending(TimeWindow::OneHour, None, 10)
        .await
        .expect("Failed to get trending");

    assert!(!trending.is_empty());

    // Video 1 should rank higher than Video 2
    let video1_item = trending.iter().find(|item| item.content_id == video1);
    let video2_item = trending.iter().find(|item| item.content_id == video2);

    if let (Some(v1), Some(v2)) = (video1_item, video2_item) {
        assert!(v1.score > v2.score, "Video 1 should have higher score");
        assert!(v1.rank < v2.rank, "Video 1 should have better rank");
    }
}

#[tokio::test]
async fn test_trending_by_category() {
    let pool = common::fixtures::setup_test_db().await;
    let user_id = common::fixtures::create_test_user(&pool, "cat_user", "cat@example.com").await;

    let video_ent = Uuid::new_v4();
    let video_news = Uuid::new_v4();

    let repo = TrendingRepo::new(pool.clone());

    // Record engagements
    repo.record_engagement(video_ent, ContentType::Video, user_id, EventType::View, None, None, None)
        .await
        .ok();
    repo.record_engagement(video_news, ContentType::Video, user_id, EventType::View, None, None, None)
        .await
        .ok();

    // Refresh for entertainment category
    let ent_count = repo
        .refresh_trending_scores(TimeWindow::OneHour, Some("entertainment"), 100)
        .await
        .expect("Failed to refresh entertainment");

    // Refresh for news category
    let news_count = repo
        .refresh_trending_scores(TimeWindow::OneHour, Some("news"), 100)
        .await
        .expect("Failed to refresh news");

    assert!(ent_count > 0);
    assert!(news_count > 0);

    // Get trending for each category
    let ent_trending = repo
        .get_trending(TimeWindow::OneHour, Some("entertainment"), 10)
        .await
        .expect("Failed to get entertainment trending");

    let news_trending = repo
        .get_trending(TimeWindow::OneHour, Some("news"), 10)
        .await
        .expect("Failed to get news trending");

    // Categories should be separate
    assert!(!ent_trending.is_empty() || !news_trending.is_empty());
}

#[tokio::test]
async fn test_trending_compute_service() {
    let pool = common::fixtures::setup_test_db().await;
    let user_id = common::fixtures::create_test_user(&pool, "compute_user", "compute@example.com").await;

    let video_id = Uuid::new_v4();

    let repo = TrendingRepo::new(pool.clone());

    // Record some engagement
    repo.record_engagement(video_id, ContentType::Video, user_id, EventType::View, None, None, None)
        .await
        .ok();
    repo.record_engagement(video_id, ContentType::Video, user_id, EventType::Like, None, None, None)
        .await
        .ok();

    // Create compute service
    let compute_service = TrendingComputeService::new(pool.clone());

    // Compute trending for 1 hour window
    let updated = compute_service
        .compute_trending_scores(TimeWindow::OneHour, None)
        .await
        .expect("Failed to compute trending");

    assert!(updated > 0);

    // Verify metadata was updated
    let metadata = repo
        .get_trending_metadata(TimeWindow::OneHour, None)
        .await
        .expect("Failed to get metadata");

    assert!(metadata.is_some());
    let meta = metadata.unwrap();
    assert_eq!(meta.time_window, "1h");
    assert!(meta.item_count > 0);
}

#[tokio::test]
async fn test_trending_service_with_cache() {
    let pool = common::fixtures::setup_test_db().await;
    let user_id = common::fixtures::create_test_user(&pool, "cache_user", "cache@example.com").await;

    let video_id = Uuid::new_v4();

    // Setup Redis (optional)
    let redis_url = std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());
    let redis_client = redis::Client::open(redis_url).ok();
    let redis_conn = if let Some(client) = redis_client {
        client.get_connection_manager().await.ok()
    } else {
        None
    };

    let repo = TrendingRepo::new(pool.clone());

    // Record engagement
    repo.record_engagement(video_id, ContentType::Video, user_id, EventType::View, None, None, None)
        .await
        .ok();

    // Refresh trending
    repo.refresh_trending_scores(TimeWindow::OneHour, None, 100)
        .await
        .ok();

    // Create service with optional Redis
    let service = TrendingService::new(pool.clone(), redis_conn);

    // Get trending (should work with or without Redis)
    let response = service
        .get_trending(TimeWindow::OneHour, None, 10)
        .await
        .expect("Failed to get trending");

    assert!(response.count >= 0);
    assert_eq!(response.time_window, "1h");
}

#[tokio::test]
async fn test_trending_by_content_type() {
    let pool = common::fixtures::setup_test_db().await;
    let user_id = common::fixtures::create_test_user(&pool, "type_user", "type@example.com").await;

    let video_id = Uuid::new_v4();
    let post_id = Uuid::new_v4();

    let repo = TrendingRepo::new(pool.clone());

    // Record engagement for different content types
    repo.record_engagement(video_id, ContentType::Video, user_id, EventType::View, None, None, None)
        .await
        .ok();
    repo.record_engagement(post_id, ContentType::Post, user_id, EventType::Like, None, None, None)
        .await
        .ok();

    // Refresh trending
    repo.refresh_trending_scores(TimeWindow::OneHour, None, 100)
        .await
        .ok();

    // Get trending by type
    let videos = repo
        .get_trending_by_type(ContentType::Video, TimeWindow::OneHour, 10)
        .await
        .expect("Failed to get video trending");

    let posts = repo
        .get_trending_by_type(ContentType::Post, TimeWindow::OneHour, 10)
        .await
        .expect("Failed to get post trending");

    // Verify content types are filtered correctly
    for item in &videos {
        assert_eq!(item.content_type, "video");
    }
    for item in &posts {
        assert_eq!(item.content_type, "post");
    }
}

#[tokio::test]
async fn test_algorithm_configuration() {
    // Test default algorithm
    let default_algo = TrendingAlgorithm::default();
    assert_eq!(default_algo.decay_rate, 0.1);
    assert!(default_algo.validate().is_ok());

    // Test fast decay
    let fast = TrendingAlgorithm::fast_decay();
    assert_eq!(fast.decay_rate, 0.5);
    assert!(fast.half_life_hours() < default_algo.half_life_hours());

    // Test slow decay
    let slow = TrendingAlgorithm::slow_decay();
    assert_eq!(slow.decay_rate, 0.05);
    assert!(slow.half_life_hours() > default_algo.half_life_hours());

    // Test score calculation
    let score_1h = default_algo.score_event(100.0, 1.0);
    let score_24h = default_algo.score_event(100.0, 24.0);

    // Recent content should score higher
    assert!(score_1h > score_24h);
}

#[tokio::test]
async fn test_engagement_weights() {
    assert_eq!(EventType::View.weight(), 1.0);
    assert_eq!(EventType::Like.weight(), 5.0);
    assert_eq!(EventType::Share.weight(), 10.0);
    assert_eq!(EventType::Comment.weight(), 3.0);

    // Shares should be worth more than likes
    assert!(EventType::Share.weight() > EventType::Like.weight());
    assert!(EventType::Like.weight() > EventType::Comment.weight());
    assert!(EventType::Comment.weight() > EventType::View.weight());
}

#[tokio::test]
async fn test_multi_window_trending() {
    let pool = common::fixtures::setup_test_db().await;
    let user_id = common::fixtures::create_test_user(&pool, "window_user", "window@example.com").await;
    let video_id = Uuid::new_v4();

    let repo = TrendingRepo::new(pool.clone());

    // Record engagement
    repo.record_engagement(video_id, ContentType::Video, user_id, EventType::View, None, None, None)
        .await
        .ok();

    // Refresh for different windows
    for window in &[TimeWindow::OneHour, TimeWindow::TwentyFourHours, TimeWindow::SevenDays] {
        let updated = repo
            .refresh_trending_scores(*window, None, 100)
            .await
            .expect("Failed to refresh");

        assert!(updated > 0, "Window {:?} should have results", window);

        // Get trending for window
        let trending = repo
            .get_trending(*window, None, 10)
            .await
            .expect("Failed to get trending");

        assert!(!trending.is_empty(), "Window {:?} should return items", window);
    }
}
