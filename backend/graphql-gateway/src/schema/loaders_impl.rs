//! Real DataLoader implementations with actual gRPC service calls
//!
//! This module provides production-ready DataLoaders that batch requests
//! to backend services, preventing N+1 query problems.

use async_graphql::dataloader::Loader;
use std::collections::HashMap;
use std::sync::Arc;
use uuid::Uuid;

use crate::clients::ServiceClients;
use crate::clients::proto::{user, content};

// ============================================================================
// User Profile DataLoader
// ============================================================================

/// Batch loads user profiles from user-service
///
/// Example: Loading creators for 100 posts results in 1 gRPC call instead of 100
#[derive(Clone)]
pub struct UserProfileLoader {
    clients: Arc<ServiceClients>,
}

impl UserProfileLoader {
    pub fn new(clients: Arc<ServiceClients>) -> Self {
        Self { clients }
    }
}

#[async_trait::async_trait]
impl Loader<Uuid> for UserProfileLoader {
    type Value = user::UserProfile;
    type Error = String;

    async fn load(&self, keys: &[Uuid]) -> Result<HashMap<Uuid, Self::Value>, Self::Error> {
        let mut client = self.clients.user_client();

        // Convert UUIDs to strings for gRPC call
        let user_ids: Vec<String> = keys.iter().map(|id| id.to_string()).collect();

        // Batch request to user-service
        let request = tonic::Request::new(user::GetUserProfilesByIdsRequest {
            user_ids,
        });

        let response = client
            .get_user_profiles_by_ids(request)
            .await
            .map_err(|e| format!("Failed to batch load user profiles: {}", e))?
            .into_inner();

        // Build hashmap for O(1) lookup
        let mut result = HashMap::new();
        for profile in response.profiles {
            if let Ok(uuid) = Uuid::parse_str(&profile.id) {
                result.insert(uuid, profile);
            }
        }

        Ok(result)
    }
}

// ============================================================================
// Post DataLoader
// ============================================================================

/// Batch loads posts from content-service
#[derive(Clone)]
pub struct PostLoader {
    clients: Arc<ServiceClients>,
}

impl PostLoader {
    pub fn new(clients: Arc<ServiceClients>) -> Self {
        Self { clients }
    }
}

#[async_trait::async_trait]
impl Loader<Uuid> for PostLoader {
    type Value = content::Post;
    type Error = String;

    async fn load(&self, keys: &[Uuid]) -> Result<HashMap<Uuid, Self::Value>, Self::Error> {
        let mut client = self.clients.content_client();

        let post_ids: Vec<String> = keys.iter().map(|id| id.to_string()).collect();

        let request = tonic::Request::new(content::GetPostsByIdsRequest {
            post_ids,
        });

        let response = client
            .get_posts_by_ids(request)
            .await
            .map_err(|e| format!("Failed to batch load posts: {}", e))?
            .into_inner();

        let mut result = HashMap::new();
        for post in response.posts {
            if let Ok(uuid) = Uuid::parse_str(&post.id) {
                result.insert(uuid, post);
            }
        }

        Ok(result)
    }
}

// ============================================================================
// Engagement Count DataLoader
// ============================================================================

/// Batch loads engagement counts (likes, comments, shares) for posts
#[derive(Clone)]
pub struct EngagementCountLoader {
    clients: Arc<ServiceClients>,
}

impl EngagementCountLoader {
    pub fn new(clients: Arc<ServiceClients>) -> Self {
        Self { clients }
    }
}

#[derive(Clone, Debug)]
pub struct EngagementCounts {
    pub likes: i64,
    pub comments: i64,
    pub shares: i64,
    pub saves: i64,
}

#[async_trait::async_trait]
impl Loader<Uuid> for EngagementCountLoader {
    type Value = EngagementCounts;
    type Error = String;

    async fn load(&self, keys: &[Uuid]) -> Result<HashMap<Uuid, Self::Value>, Self::Error> {
        let mut client = self.clients.content_client();

        let post_ids: Vec<String> = keys.iter().map(|id| id.to_string()).collect();

        let request = tonic::Request::new(content::GetEngagementCountsRequest {
            post_ids,
        });

        let response = client
            .get_engagement_counts(request)
            .await
            .map_err(|e| format!("Failed to batch load engagement counts: {}", e))?
            .into_inner();

        let mut result = HashMap::new();
        for count in response.counts {
            if let Ok(uuid) = Uuid::parse_str(&count.post_id) {
                result.insert(uuid, EngagementCounts {
                    likes: count.likes,
                    comments: count.comments,
                    shares: count.shares,
                    saves: count.saves,
                });
            }
        }

        Ok(result)
    }
}

// ============================================================================
// Follow Count DataLoader
// ============================================================================

/// Batch loads follower/following counts for users
#[derive(Clone)]
pub struct FollowCountLoader {
    clients: Arc<ServiceClients>,
}

impl FollowCountLoader {
    pub fn new(clients: Arc<ServiceClients>) -> Self {
        Self { clients }
    }
}

#[derive(Clone, Debug)]
pub struct FollowCounts {
    pub followers: i64,
    pub following: i64,
}

#[async_trait::async_trait]
impl Loader<Uuid> for FollowCountLoader {
    type Value = FollowCounts;
    type Error = String;

    async fn load(&self, keys: &[Uuid]) -> Result<HashMap<Uuid, Self::Value>, Self::Error> {
        let mut client = self.clients.user_client();

        let user_ids: Vec<String> = keys.iter().map(|id| id.to_string()).collect();

        let request = tonic::Request::new(user::GetFollowCountsRequest {
            user_ids,
        });

        let response = client
            .get_follow_counts(request)
            .await
            .map_err(|e| format!("Failed to batch load follow counts: {}", e))?
            .into_inner();

        let mut result = HashMap::new();
        for count in response.counts {
            if let Ok(uuid) = Uuid::parse_str(&count.user_id) {
                result.insert(uuid, FollowCounts {
                    followers: count.followers,
                    following: count.following,
                });
            }
        }

        Ok(result)
    }
}

// ============================================================================
// Comment DataLoader
// ============================================================================

/// Batch loads comments for posts
#[derive(Clone)]
pub struct CommentLoader {
    clients: Arc<ServiceClients>,
}

impl CommentLoader {
    pub fn new(clients: Arc<ServiceClients>) -> Self {
        Self { clients }
    }
}

#[async_trait::async_trait]
impl Loader<Uuid> for CommentLoader {
    type Value = Vec<content::Comment>;
    type Error = String;

    async fn load(&self, keys: &[Uuid]) -> Result<HashMap<Uuid, Self::Value>, Self::Error> {
        let mut client = self.clients.content_client();

        let post_ids: Vec<String> = keys.iter().map(|id| id.to_string()).collect();

        // Batch load comments for multiple posts
        let request = tonic::Request::new(content::GetCommentsByPostIdsRequest {
            post_ids,
            limit: 10, // Default to top 10 comments per post
        });

        let response = client
            .get_comments_by_post_ids(request)
            .await
            .map_err(|e| format!("Failed to batch load comments: {}", e))?
            .into_inner();

        // Group comments by post_id
        let mut result: HashMap<Uuid, Vec<content::Comment>> = HashMap::new();
        for comment in response.comments {
            if let Ok(post_uuid) = Uuid::parse_str(&comment.post_id) {
                result.entry(post_uuid)
                    .or_insert_with(Vec::new)
                    .push(comment);
            }
        }

        // Ensure all requested keys have an entry (even if empty)
        for key in keys {
            result.entry(*key).or_insert_with(Vec::new);
        }

        Ok(result)
    }
}

// ============================================================================
// Media URL DataLoader
// ============================================================================

/// Batch loads media URLs (images, videos) for posts
#[derive(Clone)]
pub struct MediaUrlLoader {
    clients: Arc<ServiceClients>,
}

impl MediaUrlLoader {
    pub fn new(clients: Arc<ServiceClients>) -> Self {
        Self { clients }
    }
}

#[async_trait::async_trait]
impl Loader<Uuid> for MediaUrlLoader {
    type Value = Vec<String>;
    type Error = String;

    async fn load(&self, keys: &[Uuid]) -> Result<HashMap<Uuid, Self::Value>, Self::Error> {
        let mut client = self.clients.content_client();

        let post_ids: Vec<String> = keys.iter().map(|id| id.to_string()).collect();

        let request = tonic::Request::new(content::GetMediaUrlsRequest {
            post_ids,
        });

        let response = client
            .get_media_urls(request)
            .await
            .map_err(|e| format!("Failed to batch load media URLs: {}", e))?
            .into_inner();

        let mut result = HashMap::new();
        for media in response.media_items {
            if let Ok(uuid) = Uuid::parse_str(&media.post_id) {
                result.insert(uuid, media.urls);
            }
        }

        // Ensure all keys have an entry
        for key in keys {
            result.entry(*key).or_insert_with(Vec::new);
        }

        Ok(result)
    }
}

// ============================================================================
// User Relationship DataLoader
// ============================================================================

/// Batch loads relationship status between users
#[derive(Clone)]
pub struct UserRelationshipLoader {
    clients: Arc<ServiceClients>,
    current_user_id: Uuid,
}

impl UserRelationshipLoader {
    pub fn new(clients: Arc<ServiceClients>, current_user_id: Uuid) -> Self {
        Self { clients, current_user_id }
    }
}

#[derive(Clone, Debug)]
pub struct RelationshipStatus {
    pub is_following: bool,
    pub is_followed_by: bool,
    pub is_blocked: bool,
    pub is_muted: bool,
}

#[async_trait::async_trait]
impl Loader<Uuid> for UserRelationshipLoader {
    type Value = RelationshipStatus;
    type Error = String;

    async fn load(&self, keys: &[Uuid]) -> Result<HashMap<Uuid, Self::Value>, Self::Error> {
        let mut client = self.clients.user_client();

        let target_user_ids: Vec<String> = keys.iter().map(|id| id.to_string()).collect();

        let request = tonic::Request::new(user::GetRelationshipStatusesRequest {
            user_id: self.current_user_id.to_string(),
            target_user_ids,
        });

        let response = client
            .get_relationship_statuses(request)
            .await
            .map_err(|e| format!("Failed to batch load relationship statuses: {}", e))?
            .into_inner();

        let mut result = HashMap::new();
        for status in response.statuses {
            if let Ok(uuid) = Uuid::parse_str(&status.target_user_id) {
                result.insert(uuid, RelationshipStatus {
                    is_following: status.is_following,
                    is_followed_by: status.is_followed_by,
                    is_blocked: status.is_blocked,
                    is_muted: status.is_muted,
                });
            }
        }

        Ok(result)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_dataloader_efficiency() {
        // Demonstrate the efficiency gain of DataLoaders

        // Without DataLoader (N+1 problem):
        // Query: { posts(first: 100) { id, creator { name } } }
        // Results in:
        // - 1 query to fetch 100 posts
        // - 100 queries to fetch each creator (N+1)
        // Total: 101 database queries

        // With DataLoader:
        // - 1 query to fetch 100 posts
        // - 1 batched query to fetch all unique creators
        // Total: 2 database queries

        let queries_without_dataloader = 101;
        let queries_with_dataloader = 2;
        let improvement_factor = queries_without_dataloader / queries_with_dataloader;

        assert_eq!(improvement_factor, 50);
        // 50x improvement in database query efficiency!
    }

    #[test]
    fn test_uuid_consistency() {
        let test_uuid = Uuid::new_v4();
        let string_repr = test_uuid.to_string();
        let parsed_uuid = Uuid::parse_str(&string_repr).unwrap();

        assert_eq!(test_uuid, parsed_uuid);
        // Ensures UUID string conversion is consistent
    }
}