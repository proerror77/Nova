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

/// Post statistics aggregated from likes, comments, shares
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PostStats {
    pub post_id: Uuid,
    pub like_count: i64,
    pub comment_count: i64,
    pub share_count: i64,
}
