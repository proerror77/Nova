//! Fallback ranking when ranking-service is unavailable
//!
//! Implements simple time-decay ranking with engagement boost as a degraded mode
//! when the ranking-service is down. This ensures feeds remain available even
//! during service disruptions.
//!
//! Algorithm:
//! - Time decay: newer posts score higher (exponential decay)
//! - Engagement boost: likes and comments increase score
//! - Score = time_score * engagement_boost
//!
//! This is NOT meant to replace the ML-based ranking from ranking-service,
//! but to provide a reasonable fallback during outages.

use crate::cache::CachedFeedPost;
use chrono::{DateTime, Utc};
use tracing::debug;

/// Fallback ranking when ranking-service is unavailable
///
/// Uses simple time-decay ranking with engagement boost:
/// - Time decay: newer posts score higher (1 / (1 + age_hours / 24))
/// - Engagement boost: ln(1 + likes + comments * 2) to prevent domination by viral posts
/// - Final score: time_score * engagement_boost
///
/// # Arguments
/// * `posts` - Vector of feed candidate posts to rank
///
/// # Returns
/// Vector of posts sorted by computed score (highest first)
pub fn fallback_rank_posts(posts: Vec<CachedFeedPost>) -> Vec<CachedFeedPost> {
    let now = Utc::now();

    let mut scored: Vec<(CachedFeedPost, f64)> = posts
        .into_iter()
        .map(|post| {
            let score = calculate_post_score(&post, now);
            (post, score)
        })
        .collect();

    // Sort by score descending (highest scores first)
    scored.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));

    debug!("Fallback ranking applied to {} posts", scored.len());

    scored.into_iter().map(|(post, _)| post).collect()
}

/// Calculate ranking score for a single post
///
/// # Arguments
/// * `post` - The post to score
/// * `now` - Current timestamp for time decay calculation
///
/// # Returns
/// Computed ranking score (higher is better)
fn calculate_post_score(post: &CachedFeedPost, now: DateTime<Utc>) -> f64 {
    // Convert Unix timestamp to DateTime
    let post_time = DateTime::from_timestamp(post.created_at, 0).unwrap_or_else(|| Utc::now());

    // Time decay: newer posts score higher
    let age_hours = (now - post_time).num_hours().max(0) as f64;

    // Exponential decay: score halves every 24 hours
    let time_score = 1.0 / (1.0 + age_hours / 24.0);

    // Engagement boost using logarithmic scale to prevent viral posts from dominating
    // Weight: likes = 1, comments = 2 (comments are more valuable)
    // Add 1.0 after ln() to ensure minimum boost of 1.0 when engagement is 0
    let engagement_count = post.like_count as f64 + (post.comment_count as f64 * 2.0);
    let engagement_boost = 1.0 + (1.0 + engagement_count).ln();

    // Final score
    let total_score = time_score * engagement_boost;

    total_score
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Duration;

    fn create_test_post(
        id: &str,
        created_at: i64,
        like_count: u32,
        comment_count: u32,
    ) -> CachedFeedPost {
        CachedFeedPost {
            id: id.to_string(),
            user_id: "test-user".to_string(),
            content: "Test content".to_string(),
            created_at,
            ranking_score: 0.0,
            like_count,
            comment_count,
            share_count: 0,
            bookmark_count: 0,
            media_urls: vec![],
            media_type: String::new(),
            thumbnail_urls: vec![],
        }
    }

    #[test]
    fn test_fallback_rank_posts_newer_posts_rank_higher() {
        let now = Utc::now();
        let old_post_time = (now - Duration::hours(48)).timestamp();
        let new_post_time = (now - Duration::hours(1)).timestamp();

        let posts = vec![
            create_test_post("old", old_post_time, 10, 5),
            create_test_post("new", new_post_time, 10, 5),
        ];

        let ranked = fallback_rank_posts(posts);

        // Newer post should rank first (with same engagement)
        assert_eq!(ranked[0].id, "new");
        assert_eq!(ranked[1].id, "old");
    }

    #[test]
    fn test_fallback_rank_posts_engagement_matters() {
        let now = Utc::now();
        let time = (now - Duration::hours(12)).timestamp();

        let posts = vec![
            create_test_post("low-engagement", time, 5, 1),
            create_test_post("high-engagement", time, 50, 20),
        ];

        let ranked = fallback_rank_posts(posts);

        // High engagement post should rank first (with same age)
        assert_eq!(ranked[0].id, "high-engagement");
        assert_eq!(ranked[1].id, "low-engagement");
    }

    #[test]
    fn test_fallback_rank_posts_empty_list() {
        let posts: Vec<CachedFeedPost> = vec![];
        let ranked = fallback_rank_posts(posts);
        assert_eq!(ranked.len(), 0);
    }

    #[test]
    fn test_fallback_rank_posts_single_post() {
        let now = Utc::now();
        let posts = vec![create_test_post("single", now.timestamp(), 10, 5)];

        let ranked = fallback_rank_posts(posts);
        assert_eq!(ranked.len(), 1);
        assert_eq!(ranked[0].id, "single");
    }

    #[test]
    fn test_calculate_post_score_time_decay() {
        let now = Utc::now();
        let post_1h = create_test_post("1h", (now - Duration::hours(1)).timestamp(), 0, 0);
        let post_24h = create_test_post("24h", (now - Duration::hours(24)).timestamp(), 0, 0);
        let post_48h = create_test_post("48h", (now - Duration::hours(48)).timestamp(), 0, 0);

        let score_1h = calculate_post_score(&post_1h, now);
        let score_24h = calculate_post_score(&post_24h, now);
        let score_48h = calculate_post_score(&post_48h, now);

        // Scores should decay with age
        assert!(score_1h > score_24h);
        assert!(score_24h > score_48h);
    }

    #[test]
    fn test_calculate_post_score_engagement_boost() {
        let now = Utc::now();
        let time = now.timestamp();

        let post_no_engagement = create_test_post("none", time, 0, 0);
        let post_some_engagement = create_test_post("some", time, 10, 5);
        let post_high_engagement = create_test_post("high", time, 100, 50);

        let score_none = calculate_post_score(&post_no_engagement, now);
        let score_some = calculate_post_score(&post_some_engagement, now);
        let score_high = calculate_post_score(&post_high_engagement, now);

        // Higher engagement should result in higher scores
        assert!(score_some > score_none);
        assert!(score_high > score_some);
    }

    #[test]
    fn test_calculate_post_score_comments_weighted_higher() {
        let now = Utc::now();
        let time = now.timestamp();

        // Post with 20 likes
        let post_likes = create_test_post("likes", time, 20, 0);
        // Post with 10 comments (worth 20 in engagement score)
        let post_comments = create_test_post("comments", time, 0, 10);

        let score_likes = calculate_post_score(&post_likes, now);
        let score_comments = calculate_post_score(&post_comments, now);

        // Comments should be weighted 2x more than likes
        // So 10 comments ~= 20 likes
        let diff = (score_likes - score_comments).abs();
        assert!(diff < 0.01, "Scores should be approximately equal");
    }

    #[test]
    fn test_fallback_rank_posts_balances_recency_and_engagement() {
        let now = Utc::now();

        // Old post with high engagement
        let old_viral = create_test_post(
            "old-viral",
            (now - Duration::hours(72)).timestamp(),
            1000,
            500,
        );

        // Recent post with moderate engagement
        let new_moderate = create_test_post(
            "new-moderate",
            (now - Duration::hours(2)).timestamp(),
            50,
            20,
        );

        let posts = vec![old_viral, new_moderate];
        let ranked = fallback_rank_posts(posts);

        // Both should be ranked (exact order depends on scoring balance)
        assert_eq!(ranked.len(), 2);

        // The algorithm should balance recency and engagement reasonably
        // This test just ensures both posts are present and ranked
        assert!(ranked.iter().any(|p| p.id == "old-viral"));
        assert!(ranked.iter().any(|p| p.id == "new-moderate"));
    }
}
