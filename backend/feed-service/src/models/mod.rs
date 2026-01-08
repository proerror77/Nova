use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Post {
    pub id: Uuid,
    pub content: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct User {
    pub id: Uuid,
    pub name: String,
}

/// Full post data for feed response (matches iOS FeedPostRaw)
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FeedPostFull {
    pub id: String,
    pub user_id: String,
    pub content: String,
    pub created_at: i64,
    pub ranking_score: f64,
    pub like_count: u32,
    pub comment_count: u32,
    pub share_count: u32,
    pub bookmark_count: u32,
    #[serde(default)]
    pub media_urls: Vec<String>,
    #[serde(default)]
    pub thumbnail_urls: Vec<String>,
    #[serde(default)]
    pub media_type: String,
    /// Whether the current user has liked this post
    #[serde(default)]
    pub is_liked: bool,
    /// Whether the current user has bookmarked this post
    #[serde(default)]
    pub is_bookmarked: bool,
    /// Author information for display
    #[serde(skip_serializing_if = "Option::is_none")]
    pub author_username: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub author_display_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub author_avatar: Option<String>,
    /// Account type when post was created: "primary" or "alias" (Issue #259)
    #[serde(default)]
    pub author_account_type: String,
}

/// Feed response model with full post objects (for iOS compatibility)
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FeedResponse {
    pub posts: Vec<FeedPostFull>,
    pub cursor: Option<String>,
    pub has_more: bool,
    pub total_count: usize,
}
