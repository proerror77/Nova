use super::{Candidate, RecallSource, RecallStrategy};
use anyhow::{Context, Result};
use async_trait::async_trait;
use redis::AsyncCommands;
use tonic::transport::Channel;
use tracing::info;

/// User-based Collaborative Filtering Recall Strategy (P1-2)
///
/// Algorithm:
/// 1. Find users similar to the target user (pre-computed similarity)
/// 2. Get recently liked/engaged posts from similar users
/// 3. Rank by similarity score and engagement recency
///
/// Data Sources:
/// - `user:{user_id}:similar` -> Sorted Set of similar users (score = similarity)
/// - BatchGetUserPosts API to fetch similar users' recent posts
///
/// Similarity is pre-computed by batch job based on:
/// - Jaccard similarity of liked items
/// - Common interaction patterns
/// - Interest overlap (from user profiles)
pub struct UserCFRecallStrategy {
    redis_client: redis::Client,
    content_client: Channel,
}

/// Redis key prefixes
const USER_SIMILAR_KEY: &str = "user:similar:";
const USER_RECENT_ITEMS_KEY: &str = "user:recent_items:";

/// Configuration
const MAX_SIMILAR_USERS: isize = 20;     // Max similar users to consider
const POSTS_PER_USER: i32 = 5;           // Posts to fetch per similar user
const MIN_USER_SIMILARITY: f64 = 0.1;    // Minimum user similarity threshold

impl UserCFRecallStrategy {
    pub fn new(redis_client: redis::Client, content_client: Channel) -> Self {
        Self {
            redis_client,
            content_client,
        }
    }

    /// Get similar users for the target user
    async fn get_similar_users(&self, user_id: &str) -> Result<Vec<(String, f64)>> {
        let mut conn = self
            .redis_client
            .get_multiplexed_async_connection()
            .await
            .context("Failed to get Redis connection")?;

        let key = format!("{}{}", USER_SIMILAR_KEY, user_id);

        // Get most similar users with their scores
        let similar: Vec<(String, f64)> = conn
            .zrevrangebyscore_withscores(&key, "+inf", MIN_USER_SIMILARITY)
            .await
            .unwrap_or_default();

        // Limit results
        let limited: Vec<(String, f64)> = similar
            .into_iter()
            .take(MAX_SIMILAR_USERS as usize)
            .collect();

        Ok(limited)
    }

    /// Get user's recent items to filter out already-seen content
    async fn get_user_seen_items(&self, user_id: &str) -> Result<std::collections::HashSet<String>> {
        let mut conn = self
            .redis_client
            .get_multiplexed_async_connection()
            .await
            .context("Failed to get Redis connection")?;

        let key = format!("{}{}", USER_RECENT_ITEMS_KEY, user_id);

        let items: Vec<String> = conn
            .zrange(&key, 0, -1)
            .await
            .unwrap_or_default();

        Ok(items.into_iter().collect())
    }

    /// Fetch recent posts from similar users using BatchGetUserPosts API
    async fn get_posts_from_similar_users(
        &self,
        similar_users: &[(String, f64)],
    ) -> Result<Vec<(String, String, f64)>> {
        // (post_id, similar_user_id, similarity_score)
        use tonic::Request;

        let user_ids: Vec<String> = similar_users.iter().map(|(id, _)| id.clone()).collect();
        let similarity_map: std::collections::HashMap<String, f64> = similar_users
            .iter()
            .map(|(id, score)| (id.clone(), *score))
            .collect();

        let mut client = content_proto::content_service_client::ContentServiceClient::new(
            self.content_client.clone(),
        );

        let request = Request::new(content_proto::BatchGetUserPostsRequest {
            user_ids,
            posts_per_user: POSTS_PER_USER,
            status: content_proto::ContentStatus::Published as i32,
        });

        let response = client
            .batch_get_user_posts(request)
            .await
            .context("Failed to call BatchGetUserPosts")?;

        let batch_response = response.into_inner();

        let mut results: Vec<(String, String, f64)> = Vec::new();

        for (similar_user_id, posts_list) in &batch_response.posts_by_user {
            let similarity = similarity_map.get(similar_user_id).copied().unwrap_or(0.5);

            for post in &posts_list.posts {
                results.push((post.id.clone(), similar_user_id.clone(), similarity));
            }
        }

        Ok(results)
    }
}

#[async_trait]
impl RecallStrategy for UserCFRecallStrategy {
    async fn recall(&self, user_id: &str, limit: i32) -> Result<Vec<Candidate>> {
        // Step 1: Get similar users
        let similar_users = self.get_similar_users(user_id).await?;

        if similar_users.is_empty() {
            info!(
                "User-CF recall: user {} has no similar users, returning empty",
                user_id
            );
            return Ok(Vec::new());
        }

        info!(
            "User-CF recall: user {} has {} similar users",
            user_id,
            similar_users.len()
        );

        // Step 2: Get user's already-seen items for filtering
        let seen_items = self.get_user_seen_items(user_id).await?;

        // Step 3: Fetch posts from similar users
        let posts_with_similarity = self.get_posts_from_similar_users(&similar_users).await?;

        // Step 4: Filter and aggregate candidates
        let mut candidate_scores: std::collections::HashMap<String, (f64, i64)> =
            std::collections::HashMap::new();

        for (post_id, _similar_user_id, similarity) in posts_with_similarity {
            // Skip already-seen items
            if seen_items.contains(&post_id) {
                continue;
            }

            // Aggregate scores (take max similarity if from multiple similar users)
            candidate_scores
                .entry(post_id)
                .and_modify(|(existing_score, _)| {
                    if similarity > *existing_score {
                        *existing_score = similarity;
                    }
                })
                .or_insert((similarity, chrono::Utc::now().timestamp()));
        }

        // Step 5: Sort by score and take top candidates
        let mut scored_candidates: Vec<(String, f64, i64)> = candidate_scores
            .into_iter()
            .map(|(post_id, (score, ts))| (post_id, score, ts))
            .collect();

        scored_candidates
            .sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));

        let candidates: Vec<Candidate> = scored_candidates
            .into_iter()
            .take(limit as usize)
            .map(|(post_id, score, timestamp)| Candidate {
                post_id,
                recall_source: RecallSource::UserCF,
                recall_weight: (score as f32).clamp(0.1, 1.0),
                timestamp,
            })
            .collect();

        info!(
            "User-CF recall: user {} retrieved {} candidates from {} similar users",
            user_id,
            candidates.len(),
            similar_users.len()
        );

        Ok(candidates)
    }

    fn source(&self) -> RecallSource {
        RecallSource::UserCF
    }
}

// Proto generated code
mod content_proto {
    tonic::include_proto!("nova.content_service.v2");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_key_format() {
        let user_id = "user123";

        let similar_key = format!("{}{}", USER_SIMILAR_KEY, user_id);
        let recent_key = format!("{}{}", USER_RECENT_ITEMS_KEY, user_id);

        assert_eq!(similar_key, "user:similar:user123");
        assert_eq!(recent_key, "user:recent_items:user123");
    }

    #[tokio::test]
    async fn test_recall_source() {
        let redis_client =
            redis::Client::open("redis://localhost:6379").expect("Redis client failed");
        let content_channel = Channel::from_static("http://localhost:9002").connect_lazy();
        let strategy = UserCFRecallStrategy::new(redis_client, content_channel);

        assert_eq!(strategy.source(), RecallSource::UserCF);
    }
}
