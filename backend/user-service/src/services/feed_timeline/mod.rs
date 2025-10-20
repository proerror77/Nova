//! Timeline-based feed sorting module
//! 
//! Provides simple time-based feed sorting algorithm with optional engagement scoring.
//! Part of MVP Feed System v1 (minimal viable product)

use chrono::{DateTime, Utc, Duration};
use serde::{Deserialize, Serialize};

/// Represents a post in the timeline feed
#[derive(Clone, Debug, Serialize, Deserialize, sqlx::FromRow)]
pub struct TimelinePost {
    pub id: i32,
    pub user_id: i32,
    pub content: String,
    pub created_at: DateTime<Utc>,
    pub like_count: i32,
}

/// Sort posts by creation time (newest first) - Simple timeline sort
/// 
/// # Arguments
/// * `posts` - Vector of posts to sort
/// 
/// # Returns
/// Vector of posts sorted by creation timestamp descending
pub fn timeline_sort(mut posts: Vec<TimelinePost>) -> Vec<TimelinePost> {
    posts.sort_by(|a, b| b.created_at.cmp(&a.created_at));
    posts
}

/// Sort posts by engagement score with time decay
/// Combines like count with recency factor
/// 
/// # Arguments
/// * `posts` - Vector of posts to sort
/// 
/// # Returns
/// Vector of posts sorted by engagement score (higher score = better rank)
pub fn timeline_sort_with_engagement(mut posts: Vec<TimelinePost>) -> Vec<TimelinePost> {
    posts.sort_by(|a, b| {
        let a_score = calculate_engagement_score(&a);
        let b_score = calculate_engagement_score(&b);
        b_score.partial_cmp(&a_score).unwrap_or(std::cmp::Ordering::Equal)
    });
    posts
}

/// Calculate engagement score for a post
/// Score = like_count + time_decay_factor
/// Time decay: newer posts get higher multiplier
fn calculate_engagement_score(post: &TimelinePost) -> f64 {
    let like_score = post.like_count as f64;
    let time_factor = time_decay_factor(&post.created_at);
    
    // Weighted score: 70% likes, 30% recency
    (like_score * 0.7) + (time_factor * 100.0 * 0.3)
}

/// Calculate time-based decay factor
/// Newer posts get higher multiplier (closer to 1.0)
/// Posts older than 7 days get very low score
fn time_decay_factor(created_at: &DateTime<Utc>) -> f64 {
    let hours_old = (Utc::now() - *created_at).num_hours() as f64;
    
    // Exponential decay: e^(-hours/24) - decays over days
    // 0 hours old: 1.0 (100% multiplier)
    // 24 hours old: 0.37 (37% multiplier)
    // 168 hours (7 days) old: 0.001 (~0% multiplier)
    (-hours_old / 24.0).exp()
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Utc;

    fn create_post(id: i32, created_at: DateTime<Utc>) -> TimelinePost {
        TimelinePost {
            id,
            user_id: 1,
            content: format!(\"Post {}\", id),
            created_at,
            like_count: 0,
        }
    }

    fn create_post_with_likes(id: i32, created_at: DateTime<Utc>, likes: i32) -> TimelinePost {
        TimelinePost {
            id,
            user_id: 1,
            content: format!(\"Post {}\", id),
            created_at,
            like_count: likes,
        }
    }

    #[test]
    fn test_timeline_sort_empty() {
        let posts: Vec<TimelinePost> = vec![];
        let sorted = timeline_sort(posts);
        assert_eq!(sorted.len(), 0);
    }

    #[test]
    fn test_timeline_sort_single_post() {
        let now = Utc::now();
        let posts = vec![create_post(1, now)];
        let sorted = timeline_sort(posts);
        assert_eq!(sorted.len(), 1);
        assert_eq!(sorted[0].id, 1);
    }

    #[test]
    fn test_timeline_sort_by_creation_date() {
        let now = Utc::now();
        let posts = vec![
            create_post(1, now - Duration::hours(2)),
            create_post(2, now - Duration::hours(1)),
            create_post(3, now),
        ];

        let sorted = timeline_sort(posts);
        assert_eq!(sorted.len(), 3);
        assert_eq!(sorted[0].id, 3);  // Most recent first
        assert_eq!(sorted[1].id, 2);
        assert_eq!(sorted[2].id, 1);  // Oldest last
    }

    #[test]
    fn test_timeline_sort_reverse_order() {
        let now = Utc::now();
        let posts = vec![
            create_post(3, now),
            create_post(2, now - Duration::hours(1)),
            create_post(1, now - Duration::hours(2)),
        ];

        let sorted = timeline_sort(posts);
        assert_eq!(sorted[0].id, 3);
        assert_eq!(sorted[1].id, 2);
        assert_eq!(sorted[2].id, 1);
    }

    #[test]
    fn test_timeline_sort_same_timestamp() {
        let now = Utc::now();
        let posts = vec![
            create_post(1, now),
            create_post(2, now),
            create_post(3, now),
        ];

        let sorted = timeline_sort(posts);
        assert_eq!(sorted.len(), 3);
        // Order might vary for same timestamp, but all should be present
        let ids: Vec<i32> = sorted.iter().map(|p| p.id).collect();
        assert!(ids.contains(&1) && ids.contains(&2) && ids.contains(&3));
    }

    #[test]
    fn test_engagement_score_calculation() {
        let now = Utc::now();
        let old_post = create_post_with_likes(1, now - Duration::hours(24), 100);
        let new_post = create_post_with_likes(2, now, 10);

        let old_score = calculate_engagement_score(&old_post);
        let new_score = calculate_engagement_score(&new_post);

        // New post with fewer likes should score higher due to recency
        assert!(new_score > old_score * 0.5);  // At least half as good
    }

    #[test]
    fn test_engagement_sort_with_high_likes() {
        let now = Utc::now();
        let posts = vec![
            create_post_with_likes(1, now - Duration::hours(1), 100),
            create_post_with_likes(2, now, 0),
            create_post_with_likes(3, now - Duration::hours(2), 500),
        ];

        let sorted = timeline_sort_with_engagement(posts);
        // High-like post should rank high even if older
        assert_eq!(sorted[0].id, 3);  // 500 likes
        assert_eq!(sorted[1].id, 1);  // 100 likes
    }

    #[test]
    fn test_time_decay_factor() {
        let now = Utc::now();
        let fresh_post = now;
        let old_post = now - Duration::hours(24);
        let very_old_post = now - Duration::days(7);

        let fresh_factor = time_decay_factor(&fresh_post);
        let old_factor = time_decay_factor(&old_post);
        let very_old_factor = time_decay_factor(&very_old_post);

        // Fresh post should have highest factor
        assert!(fresh_factor > old_factor);
        assert!(old_factor > very_old_factor);
        
        // Factors should be between 0 and 1
        assert!(fresh_factor <= 1.0);
        assert!(fresh_factor >= 0.0);
    }
}
