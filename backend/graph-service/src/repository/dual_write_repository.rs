use super::graph_repository::GraphRepository;
use super::postgres_repository::PostgresGraphRepository;
use crate::domain::edge::GraphStats;
use anyhow::{Context, Result};
use std::sync::Arc;
use tracing::{error, warn};
use uuid::Uuid;

/// Dual-write repository: PostgreSQL (source of truth) + Neo4j (read optimization)
#[derive(Clone)]
pub struct DualWriteRepository {
    postgres: PostgresGraphRepository,
    neo4j: Arc<GraphRepository>,
    /// If true, fail on Neo4j errors. If false, only log warnings
    strict_mode: bool,
}

impl DualWriteRepository {
    pub fn new(
        postgres: PostgresGraphRepository,
        neo4j: Arc<GraphRepository>,
        strict_mode: bool,
    ) -> Self {
        Self {
            postgres,
            neo4j,
            strict_mode,
        }
    }

    /// Health check both databases
    pub async fn health_check(&self) -> Result<(bool, bool)> {
        let pg_healthy = self.postgres.health_check().await.unwrap_or(false);
        let neo4j_healthy = self.neo4j.health_check().await.unwrap_or(false);
        Ok((pg_healthy, neo4j_healthy))
    }

    /// Create follow with dual-write
    pub async fn create_follow(&self, follower_id: Uuid, followee_id: Uuid) -> Result<()> {
        // Step 1: Write to PostgreSQL (source of truth) - MUST succeed
        self.postgres
            .create_follow(follower_id, followee_id)
            .await
            .context("Failed to write follow to PostgreSQL")?;

        // Step 2: Write to Neo4j (optimization) - log error but don't fail
        if let Err(e) = self.neo4j.create_follow(follower_id, followee_id).await {
            error!(
                "Neo4j write failed for FOLLOWS ({} -> {}): {}",
                follower_id, followee_id, e
            );

            // Increment failure metric
            metrics::counter!("neo4j.write.failure", "operation" => "create_follow").increment(1);

            if self.strict_mode {
                // In strict mode, rollback PostgreSQL write
                warn!("Strict mode: rolling back PostgreSQL follow due to Neo4j failure");
                self.postgres
                    .delete_follow(follower_id, followee_id)
                    .await
                    .ok(); // Best effort rollback
                return Err(e);
            } else {
                // In non-strict mode, continue despite Neo4j failure
                warn!(
                    "Non-strict mode: PostgreSQL write succeeded but Neo4j failed (data drift possible)"
                );
            }
        } else {
            metrics::counter!("neo4j.write.success", "operation" => "create_follow").increment(1);
        }

        Ok(())
    }

    /// Delete follow with dual-write
    pub async fn delete_follow(&self, follower_id: Uuid, followee_id: Uuid) -> Result<()> {
        // PostgreSQL first (source of truth)
        self.postgres
            .delete_follow(follower_id, followee_id)
            .await
            .context("Failed to delete follow from PostgreSQL")?;

        // Neo4j second (best effort)
        if let Err(e) = self.neo4j.delete_follow(follower_id, followee_id).await {
            error!(
                "Neo4j delete failed for FOLLOWS ({} -> {}): {}",
                follower_id, followee_id, e
            );
            metrics::counter!("neo4j.write.failure", "operation" => "delete_follow").increment(1);

            if self.strict_mode {
                return Err(e);
            }
        } else {
            metrics::counter!("neo4j.write.success", "operation" => "delete_follow").increment(1);
        }

        Ok(())
    }

    /// Create mute with dual-write
    pub async fn create_mute(&self, muter_id: Uuid, mutee_id: Uuid) -> Result<()> {
        self.postgres
            .create_mute(muter_id, mutee_id)
            .await
            .context("Failed to write mute to PostgreSQL")?;

        if let Err(e) = self.neo4j.create_mute(muter_id, mutee_id).await {
            error!("Neo4j write failed for MUTES ({} -> {}): {}", muter_id, mutee_id, e);
            metrics::counter!("neo4j.write.failure", "operation" => "create_mute").increment(1);

            if self.strict_mode {
                self.postgres.delete_mute(muter_id, mutee_id).await.ok();
                return Err(e);
            }
        } else {
            metrics::counter!("neo4j.write.success", "operation" => "create_mute").increment(1);
        }

        Ok(())
    }

    /// Delete mute with dual-write
    pub async fn delete_mute(&self, muter_id: Uuid, mutee_id: Uuid) -> Result<()> {
        self.postgres
            .delete_mute(muter_id, mutee_id)
            .await
            .context("Failed to delete mute from PostgreSQL")?;

        if let Err(e) = self.neo4j.delete_mute(muter_id, mutee_id).await {
            error!("Neo4j delete failed for MUTES ({} -> {}): {}", muter_id, mutee_id, e);
            metrics::counter!("neo4j.write.failure", "operation" => "delete_mute").increment(1);

            if self.strict_mode {
                return Err(e);
            }
        } else {
            metrics::counter!("neo4j.write.success", "operation" => "delete_mute").increment(1);
        }

        Ok(())
    }

    /// Create block with dual-write
    pub async fn create_block(&self, blocker_id: Uuid, blocked_id: Uuid) -> Result<()> {
        self.postgres
            .create_block(blocker_id, blocked_id)
            .await
            .context("Failed to write block to PostgreSQL")?;

        if let Err(e) = self.neo4j.create_block(blocker_id, blocked_id).await {
            error!(
                "Neo4j write failed for BLOCKS ({} -> {}): {}",
                blocker_id, blocked_id, e
            );
            metrics::counter!("neo4j.write.failure", "operation" => "create_block").increment(1);

            if self.strict_mode {
                self.postgres
                    .delete_block(blocker_id, blocked_id)
                    .await
                    .ok();
                return Err(e);
            }
        } else {
            metrics::counter!("neo4j.write.success", "operation" => "create_block").increment(1);
        }

        Ok(())
    }

    /// Delete block with dual-write
    pub async fn delete_block(&self, blocker_id: Uuid, blocked_id: Uuid) -> Result<()> {
        self.postgres
            .delete_block(blocker_id, blocked_id)
            .await
            .context("Failed to delete block from PostgreSQL")?;

        if let Err(e) = self.neo4j.delete_block(blocker_id, blocked_id).await {
            error!(
                "Neo4j delete failed for BLOCKS ({} -> {}): {}",
                blocker_id, blocked_id, e
            );
            metrics::counter!("neo4j.write.failure", "operation" => "delete_block").increment(1);

            if self.strict_mode {
                return Err(e);
            }
        } else {
            metrics::counter!("neo4j.write.success", "operation" => "delete_block").increment(1);
        }

        Ok(())
    }

    /// Get followers (Neo4j first, PostgreSQL fallback)
    pub async fn get_followers(
        &self,
        user_id: Uuid,
        limit: i32,
        offset: i32,
    ) -> Result<(Vec<Uuid>, i32, bool)> {
        let start = std::time::Instant::now();

        match self.neo4j.get_followers(user_id, limit, offset).await {
            Ok(result) => {
                let duration = start.elapsed();
                metrics::histogram!("neo4j.query.duration", "operation" => "get_followers")
                    .record(duration.as_millis() as f64);
                metrics::counter!("neo4j.query.success", "operation" => "get_followers")
                    .increment(1);
                Ok(result)
            }
            Err(e) => {
                error!("Neo4j get_followers failed, falling back to PostgreSQL: {}", e);
                metrics::counter!("neo4j.query.failure", "operation" => "get_followers")
                    .increment(1);

                let result = self.postgres.get_followers(user_id, limit, offset).await?;
                metrics::counter!("postgres.query.fallback", "operation" => "get_followers")
                    .increment(1);
                Ok(result)
            }
        }
    }

    /// Get following (Neo4j first, PostgreSQL fallback)
    pub async fn get_following(
        &self,
        user_id: Uuid,
        limit: i32,
        offset: i32,
    ) -> Result<(Vec<Uuid>, i32, bool)> {
        let start = std::time::Instant::now();

        match self.neo4j.get_following(user_id, limit, offset).await {
            Ok(result) => {
                let duration = start.elapsed();
                metrics::histogram!("neo4j.query.duration", "operation" => "get_following")
                    .record(duration.as_millis() as f64);
                metrics::counter!("neo4j.query.success", "operation" => "get_following")
                    .increment(1);
                Ok(result)
            }
            Err(e) => {
                error!("Neo4j get_following failed, falling back to PostgreSQL: {}", e);
                metrics::counter!("neo4j.query.failure", "operation" => "get_following")
                    .increment(1);

                let result = self.postgres.get_following(user_id, limit, offset).await?;
                metrics::counter!("postgres.query.fallback", "operation" => "get_following")
                    .increment(1);
                Ok(result)
            }
        }
    }

    /// Check if following (Neo4j first, PostgreSQL fallback)
    pub async fn is_following(&self, follower_id: Uuid, followee_id: Uuid) -> Result<bool> {
        match self.neo4j.is_following(follower_id, followee_id).await {
            Ok(result) => {
                metrics::counter!("neo4j.query.success", "operation" => "is_following")
                    .increment(1);
                Ok(result)
            }
            Err(e) => {
                error!("Neo4j is_following failed, falling back to PostgreSQL: {}", e);
                metrics::counter!("neo4j.query.failure", "operation" => "is_following")
                    .increment(1);

                let result = self.postgres.is_following(follower_id, followee_id).await?;
                metrics::counter!("postgres.query.fallback", "operation" => "is_following")
                    .increment(1);
                Ok(result)
            }
        }
    }

    /// Check if muted (Neo4j only, no PostgreSQL fallback yet)
    pub async fn is_muted(&self, muter_id: Uuid, mutee_id: Uuid) -> Result<bool> {
        self.neo4j.is_muted(muter_id, mutee_id).await
    }

    /// Check if blocked (Neo4j only)
    pub async fn is_blocked(&self, blocker_id: Uuid, blocked_id: Uuid) -> Result<bool> {
        self.neo4j.is_blocked(blocker_id, blocked_id).await
    }

    /// Batch check following (Neo4j only - PostgreSQL would be too slow)
    pub async fn batch_check_following(
        &self,
        follower_id: Uuid,
        followee_ids: Vec<Uuid>,
    ) -> Result<std::collections::HashMap<String, bool>> {
        self.neo4j
            .batch_check_following(follower_id, followee_ids)
            .await
    }

    /// Get graph stats (Neo4j only - complex query)
    pub async fn get_graph_stats(&self, user_id: Uuid) -> Result<GraphStats> {
        self.neo4j.get_graph_stats(user_id).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    #[ignore]
    async fn test_dual_write() {
        // Test dual-write behavior with mock repositories
        // Implementation left as exercise
    }
}
