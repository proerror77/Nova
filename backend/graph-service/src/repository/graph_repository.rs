use crate::domain::edge::GraphStats;
use anyhow::{Context, Result};
use neo4rs::{query, Graph};
use std::sync::Arc;
use tracing::debug;
use uuid::Uuid;

/// Repository for graph operations using Neo4j
#[derive(Clone)]
pub struct GraphRepository {
    graph: Arc<Graph>,
}

impl GraphRepository {
    pub async fn new(uri: &str, user: &str, password: &str) -> Result<Self> {
        let graph = Graph::new(uri, user, password)
            .await
            .context("Failed to connect to Neo4j")?;

        Ok(Self {
            graph: Arc::new(graph),
        })
    }

    /// Health check - verify Neo4j connection
    pub async fn health_check(&self) -> Result<bool> {
        let mut result = self
            .graph
            .execute(query("RETURN 1 AS health"))
            .await
            .context("Health check query failed")?;

        if let Some(row) = result.next().await? {
            let health: i64 = row.get("health").unwrap_or(0);
            Ok(health == 1)
        } else {
            Ok(false)
        }
    }

    /// Ensure user node exists (idempotent)
    async fn ensure_user_node(&self, user_id: Uuid) -> Result<()> {
        let cypher = r#"
            MERGE (u:User {id: $id})
            ON CREATE SET u.created_at = timestamp()
            RETURN u.id
        "#;

        let mut result = self
            .graph
            .execute(query(cypher).param("id", user_id.to_string()))
            .await
            .context("Failed to ensure user node")?;

        // Drain result stream
        while result.next().await?.is_some() {}

        debug!("Ensured user node exists: {}", user_id);
        Ok(())
    }

    /// Create FOLLOWS edge
    pub async fn create_follow(&self, follower_id: Uuid, followee_id: Uuid) -> Result<()> {
        if follower_id == followee_id {
            return Err(anyhow::anyhow!("Cannot follow self"));
        }

        // Ensure both users exist
        self.ensure_user_node(follower_id).await?;
        self.ensure_user_node(followee_id).await?;

        let cypher = r#"
            MATCH (a:User {id: $follower}), (b:User {id: $followee})
            MERGE (a)-[r:FOLLOWS]->(b)
            ON CREATE SET r.created_at = timestamp()
            RETURN r.created_at
        "#;

        let mut result = self
            .graph
            .execute(
                query(cypher)
                    .param("follower", follower_id.to_string())
                    .param("followee", followee_id.to_string()),
            )
            .await
            .context("Failed to create FOLLOWS edge")?;

        while result.next().await?.is_some() {}

        debug!("Created FOLLOWS: {} -> {}", follower_id, followee_id);
        Ok(())
    }

    /// Delete FOLLOWS edge
    pub async fn delete_follow(&self, follower_id: Uuid, followee_id: Uuid) -> Result<()> {
        let cypher = r#"
            MATCH (a:User {id: $follower})-[r:FOLLOWS]->(b:User {id: $followee})
            DELETE r
        "#;

        let mut result = self
            .graph
            .execute(
                query(cypher)
                    .param("follower", follower_id.to_string())
                    .param("followee", followee_id.to_string()),
            )
            .await
            .context("Failed to delete FOLLOWS edge")?;

        while result.next().await?.is_some() {}

        debug!("Deleted FOLLOWS: {} -> {}", follower_id, followee_id);
        Ok(())
    }

    /// Create MUTES edge
    pub async fn create_mute(&self, muter_id: Uuid, mutee_id: Uuid) -> Result<()> {
        if muter_id == mutee_id {
            return Err(anyhow::anyhow!("Cannot mute self"));
        }

        self.ensure_user_node(muter_id).await?;
        self.ensure_user_node(mutee_id).await?;

        let cypher = r#"
            MATCH (a:User {id: $muter}), (b:User {id: $mutee})
            MERGE (a)-[r:MUTES]->(b)
            ON CREATE SET r.created_at = timestamp()
            RETURN r.created_at
        "#;

        let mut result = self
            .graph
            .execute(
                query(cypher)
                    .param("muter", muter_id.to_string())
                    .param("mutee", mutee_id.to_string()),
            )
            .await
            .context("Failed to create MUTES edge")?;

        while result.next().await?.is_some() {}

        debug!("Created MUTES: {} -> {}", muter_id, mutee_id);
        Ok(())
    }

    /// Delete MUTES edge
    pub async fn delete_mute(&self, muter_id: Uuid, mutee_id: Uuid) -> Result<()> {
        let cypher = r#"
            MATCH (a:User {id: $muter})-[r:MUTES]->(b:User {id: $mutee})
            DELETE r
        "#;

        let mut result = self
            .graph
            .execute(
                query(cypher)
                    .param("muter", muter_id.to_string())
                    .param("mutee", mutee_id.to_string()),
            )
            .await
            .context("Failed to delete MUTES edge")?;

        while result.next().await?.is_some() {}

        debug!("Deleted MUTES: {} -> {}", muter_id, mutee_id);
        Ok(())
    }

    /// Create BLOCKS edge
    pub async fn create_block(&self, blocker_id: Uuid, blocked_id: Uuid) -> Result<()> {
        if blocker_id == blocked_id {
            return Err(anyhow::anyhow!("Cannot block self"));
        }

        self.ensure_user_node(blocker_id).await?;
        self.ensure_user_node(blocked_id).await?;

        let cypher = r#"
            MATCH (a:User {id: $blocker}), (b:User {id: $blocked})
            MERGE (a)-[r:BLOCKS]->(b)
            ON CREATE SET r.created_at = timestamp()
            RETURN r.created_at
        "#;

        let mut result = self
            .graph
            .execute(
                query(cypher)
                    .param("blocker", blocker_id.to_string())
                    .param("blocked", blocked_id.to_string()),
            )
            .await
            .context("Failed to create BLOCKS edge")?;

        while result.next().await?.is_some() {}

        debug!("Created BLOCKS: {} -> {}", blocker_id, blocked_id);
        Ok(())
    }

    /// Delete BLOCKS edge
    pub async fn delete_block(&self, blocker_id: Uuid, blocked_id: Uuid) -> Result<()> {
        let cypher = r#"
            MATCH (a:User {id: $blocker})-[r:BLOCKS]->(b:User {id: $blocked})
            DELETE r
        "#;

        let mut result = self
            .graph
            .execute(
                query(cypher)
                    .param("blocker", blocker_id.to_string())
                    .param("blocked", blocked_id.to_string()),
            )
            .await
            .context("Failed to delete BLOCKS edge")?;

        while result.next().await?.is_some() {}

        debug!("Deleted BLOCKS: {} -> {}", blocker_id, blocked_id);
        Ok(())
    }

    /// Get followers of a user (who follows this user)
    pub async fn get_followers(
        &self,
        user_id: Uuid,
        limit: i32,
        offset: i32,
    ) -> Result<(Vec<Uuid>, i32, bool)> {
        // Max limit enforcement (10,000 as per spec)
        let effective_limit = limit.min(10000);

        // Get total count
        let count_cypher = r#"
            MATCH (follower:User)-[:FOLLOWS]->(user:User {id: $user_id})
            RETURN count(follower) AS total
        "#;

        let mut count_result = self
            .graph
            .execute(query(count_cypher).param("user_id", user_id.to_string()))
            .await
            .context("Failed to count followers")?;

        let total_count: i32 = if let Some(row) = count_result.next().await? {
            row.get("total").unwrap_or(0)
        } else {
            0
        };

        // Get paginated followers
        let cypher = r#"
            MATCH (follower:User)-[:FOLLOWS]->(user:User {id: $user_id})
            RETURN follower.id AS follower_id
            ORDER BY follower.id
            SKIP $offset
            LIMIT $limit
        "#;

        let mut result = self
            .graph
            .execute(
                query(cypher)
                    .param("user_id", user_id.to_string())
                    .param("offset", offset as i64)
                    .param("limit", effective_limit as i64),
            )
            .await
            .context("Failed to get followers")?;

        let mut followers = Vec::new();
        while let Some(row) = result.next().await? {
            if let Ok(id_str) = row.get::<String>("follower_id") {
                if let Ok(follower_id) = Uuid::parse_str(&id_str) {
                    followers.push(follower_id);
                }
            }
        }

        let has_more = (offset + effective_limit) < total_count;

        debug!(
            "Got {} followers for user {} (offset: {}, has_more: {})",
            followers.len(),
            user_id,
            offset,
            has_more
        );

        Ok((followers, total_count, has_more))
    }

    /// Get following list of a user (who this user follows)
    pub async fn get_following(
        &self,
        user_id: Uuid,
        limit: i32,
        offset: i32,
    ) -> Result<(Vec<Uuid>, i32, bool)> {
        let effective_limit = limit.min(10000);

        // Get total count
        let count_cypher = r#"
            MATCH (user:User {id: $user_id})-[:FOLLOWS]->(following:User)
            RETURN count(following) AS total
        "#;

        let mut count_result = self
            .graph
            .execute(query(count_cypher).param("user_id", user_id.to_string()))
            .await
            .context("Failed to count following")?;

        let total_count: i32 = if let Some(row) = count_result.next().await? {
            row.get("total").unwrap_or(0)
        } else {
            0
        };

        // Get paginated following list
        let cypher = r#"
            MATCH (user:User {id: $user_id})-[:FOLLOWS]->(following:User)
            RETURN following.id AS following_id
            ORDER BY following.id
            SKIP $offset
            LIMIT $limit
        "#;

        let mut result = self
            .graph
            .execute(
                query(cypher)
                    .param("user_id", user_id.to_string())
                    .param("offset", offset as i64)
                    .param("limit", effective_limit as i64),
            )
            .await
            .context("Failed to get following list")?;

        let mut following = Vec::new();
        while let Some(row) = result.next().await? {
            if let Ok(id_str) = row.get::<String>("following_id") {
                if let Ok(following_id) = Uuid::parse_str(&id_str) {
                    following.push(following_id);
                }
            }
        }

        let has_more = (offset + effective_limit) < total_count;

        debug!(
            "Got {} following for user {} (offset: {}, has_more: {})",
            following.len(),
            user_id,
            offset,
            has_more
        );

        Ok((following, total_count, has_more))
    }

    /// Check if user A follows user B
    pub async fn is_following(&self, follower_id: Uuid, followee_id: Uuid) -> Result<bool> {
        let cypher = r#"
            MATCH (a:User {id: $follower})-[r:FOLLOWS]->(b:User {id: $followee})
            RETURN count(r) > 0 AS is_following
        "#;

        let mut result = self
            .graph
            .execute(
                query(cypher)
                    .param("follower", follower_id.to_string())
                    .param("followee", followee_id.to_string()),
            )
            .await
            .context("Failed to check following status")?;

        if let Some(row) = result.next().await? {
            Ok(row.get("is_following").unwrap_or(false))
        } else {
            Ok(false)
        }
    }

    /// Check if user A mutes user B
    pub async fn is_muted(&self, muter_id: Uuid, mutee_id: Uuid) -> Result<bool> {
        let cypher = r#"
            MATCH (a:User {id: $muter})-[r:MUTES]->(b:User {id: $mutee})
            RETURN count(r) > 0 AS is_muted
        "#;

        let mut result = self
            .graph
            .execute(
                query(cypher)
                    .param("muter", muter_id.to_string())
                    .param("mutee", mutee_id.to_string()),
            )
            .await
            .context("Failed to check mute status")?;

        if let Some(row) = result.next().await? {
            Ok(row.get("is_muted").unwrap_or(false))
        } else {
            Ok(false)
        }
    }

    /// Check if user A blocks user B
    pub async fn is_blocked(&self, blocker_id: Uuid, blocked_id: Uuid) -> Result<bool> {
        let cypher = r#"
            MATCH (a:User {id: $blocker})-[r:BLOCKS]->(b:User {id: $blocked})
            RETURN count(r) > 0 AS is_blocked
        "#;

        let mut result = self
            .graph
            .execute(
                query(cypher)
                    .param("blocker", blocker_id.to_string())
                    .param("blocked", blocked_id.to_string()),
            )
            .await
            .context("Failed to check block status")?;

        if let Some(row) = result.next().await? {
            Ok(row.get("is_blocked").unwrap_or(false))
        } else {
            Ok(false)
        }
    }

    /// Batch check if follower follows multiple users
    /// Max 100 followee_ids as per spec
    pub async fn batch_check_following(
        &self,
        follower_id: Uuid,
        followee_ids: Vec<Uuid>,
    ) -> Result<std::collections::HashMap<String, bool>> {
        if followee_ids.len() > 100 {
            return Err(anyhow::anyhow!("Max 100 followee_ids allowed"));
        }

        let followee_id_strings: Vec<String> =
            followee_ids.iter().map(|id| id.to_string()).collect();

        let cypher = r#"
            MATCH (follower:User {id: $follower})
            UNWIND $followee_ids AS followee_id
            OPTIONAL MATCH (follower)-[r:FOLLOWS]->(followee:User {id: followee_id})
            RETURN followee_id, r IS NOT NULL AS is_following
        "#;

        let mut result = self
            .graph
            .execute(
                query(cypher)
                    .param("follower", follower_id.to_string())
                    .param("followee_ids", followee_id_strings),
            )
            .await
            .context("Failed to batch check following")?;

        let mut results = std::collections::HashMap::new();
        while let Some(row) = result.next().await? {
            if let Ok(followee_id) = row.get::<String>("followee_id") {
                let is_following: bool = row.get("is_following").unwrap_or(false);
                results.insert(followee_id, is_following);
            }
        }

        debug!(
            "Batch checked {} followee_ids for follower {}",
            results.len(),
            follower_id
        );

        Ok(results)
    }

    /// Get graph stats for a user (followers/following/muted/blocked counts)
    pub async fn get_graph_stats(&self, user_id: Uuid) -> Result<GraphStats> {
        let cypher = r#"
            MATCH (user:User {id: $user_id})
            OPTIONAL MATCH (follower:User)-[:FOLLOWS]->(user)
            WITH user, count(follower) AS followers_count
            OPTIONAL MATCH (user)-[:FOLLOWS]->(following:User)
            WITH user, followers_count, count(following) AS following_count
            OPTIONAL MATCH (user)-[:MUTES]->(muted:User)
            WITH user, followers_count, following_count, count(muted) AS muted_count
            OPTIONAL MATCH (user)-[:BLOCKS]->(blocked:User)
            RETURN
                followers_count,
                following_count,
                muted_count,
                count(blocked) AS blocked_count
        "#;

        let mut result = self
            .graph
            .execute(query(cypher).param("user_id", user_id.to_string()))
            .await
            .context("Failed to get graph stats")?;

        if let Some(row) = result.next().await? {
            Ok(GraphStats {
                user_id,
                followers_count: row.get("followers_count").unwrap_or(0),
                following_count: row.get("following_count").unwrap_or(0),
                muted_count: row.get("muted_count").unwrap_or(0),
                blocked_count: row.get("blocked_count").unwrap_or(0),
            })
        } else {
            Ok(GraphStats::default())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // NOTE: These tests require a running Neo4j instance
    // Run with: docker run -p 7687:7687 -e NEO4J_AUTH=neo4j/password neo4j:5

    #[tokio::test]
    #[ignore] // Ignore by default, run manually with: cargo test -- --ignored
    async fn test_create_follow() {
        let repo = GraphRepository::new("bolt://localhost:7687", "neo4j", "password")
            .await
            .expect("Failed to connect to Neo4j");

        let follower = Uuid::new_v4();
        let followee = Uuid::new_v4();

        repo.create_follow(follower, followee)
            .await
            .expect("Failed to create follow");

        let is_following = repo
            .is_following(follower, followee)
            .await
            .expect("Failed to check following");

        assert!(is_following);

        // Cleanup
        repo.delete_follow(follower, followee)
            .await
            .expect("Failed to delete follow");
    }

    #[tokio::test]
    #[ignore]
    async fn test_batch_check_following() {
        let repo = GraphRepository::new("bolt://localhost:7687", "neo4j", "password")
            .await
            .expect("Failed to connect to Neo4j");

        let follower = Uuid::new_v4();
        let followee1 = Uuid::new_v4();
        let followee2 = Uuid::new_v4();
        let followee3 = Uuid::new_v4();

        // Create follows
        repo.create_follow(follower, followee1)
            .await
            .expect("Failed to create follow");
        repo.create_follow(follower, followee2)
            .await
            .expect("Failed to create follow");

        // Batch check
        let results = repo
            .batch_check_following(follower, vec![followee1, followee2, followee3])
            .await
            .expect("Failed to batch check");

        assert_eq!(results.get(&followee1.to_string()), Some(&true));
        assert_eq!(results.get(&followee2.to_string()), Some(&true));
        assert_eq!(results.get(&followee3.to_string()), Some(&false));

        // Cleanup
        repo.delete_follow(follower, followee1).await.ok();
        repo.delete_follow(follower, followee2).await.ok();
    }
}
