use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Like entity - represents a user liking a post
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Like {
    pub id: Uuid,
    pub user_id: Uuid,
    pub post_id: Uuid,
    pub created_at: DateTime<Utc>,
}

/// Comment entity - represents a comment on a post
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Comment {
    pub id: Uuid,
    pub post_id: Uuid,
    pub user_id: Uuid,
    pub content: String,
    pub parent_comment_id: Option<Uuid>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Share entity - represents a user sharing a post
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Share {
    pub id: Uuid,
    pub user_id: Uuid,
    pub post_id: Uuid,
    pub share_type: String,
    pub created_at: DateTime<Utc>,
}

/// Bookmark entity - represents a user bookmarking/saving a post
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Bookmark {
    pub id: Uuid,
    pub user_id: Uuid,
    pub post_id: Uuid,
    pub bookmarked_at: DateTime<Utc>,
    pub collection_id: Option<Uuid>,
}

/// Bookmark collection - represents a folder for organizing bookmarks
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct BookmarkCollection {
    pub id: Uuid,
    pub user_id: Uuid,
    pub name: String,
    pub description: Option<String>,
    pub is_private: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Post statistics aggregated from likes, comments, shares
#[allow(dead_code)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PostStats {
    pub post_id: Uuid,
    pub like_count: i64,
    pub comment_count: i64,
    pub share_count: i64,
}

// ============================================================================
// Poll Models (投票榜单)
// ============================================================================

/// Poll entity - represents a voting poll/leaderboard
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Poll {
    pub id: Uuid,
    pub title: String,
    pub description: Option<String>,
    pub cover_image_url: Option<String>,
    pub creator_id: Uuid,
    pub poll_type: String,
    pub status: String,
    pub total_votes: i64,
    pub candidate_count: i32,
    pub tags: Vec<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub ends_at: Option<DateTime<Utc>>,
    pub is_deleted: bool,
}

/// Poll candidate - represents a candidate in a poll
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct PollCandidate {
    pub id: Uuid,
    pub poll_id: Uuid,
    pub name: String,
    pub avatar_url: Option<String>,
    pub description: Option<String>,
    pub user_id: Option<Uuid>,
    pub vote_count: i64,
    pub position: i32,
    pub created_at: DateTime<Utc>,
    pub is_deleted: bool,
}

/// Poll vote - represents a user's vote on a poll
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct PollVote {
    pub id: Uuid,
    pub poll_id: Uuid,
    pub candidate_id: Uuid,
    pub user_id: Uuid,
    pub created_at: DateTime<Utc>,
}

/// Candidate with rank information (for rankings query)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CandidateWithRank {
    pub id: Uuid,
    pub name: String,
    pub avatar_url: Option<String>,
    pub description: Option<String>,
    pub user_id: Option<Uuid>,
    pub vote_count: i64,
    pub rank: i32,
    pub rank_change: i32,
    pub vote_percentage: f64,
}

/// Candidate preview for poll summary
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CandidatePreview {
    pub id: Uuid,
    pub name: String,
    pub avatar_url: Option<String>,
    pub rank: i32,
}
