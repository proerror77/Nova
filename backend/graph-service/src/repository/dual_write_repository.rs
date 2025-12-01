use super::graph_repository::GraphRepository;
use super::postgres_repository::PostgresGraphRepository;
use super::GraphRepositoryTrait;
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

    /// Helper: Execute dual-write with automatic rollback on Neo4j failure (strict mode only)
    async fn execute_dual_write<PgFut, Neo4jFut, RollbackFut>(
        &self,
        operation: &str,
        edge_desc: String,
        pg_write: PgFut,
        neo4j_write: Neo4jFut,
        pg_rollback: Option<RollbackFut>,
    ) -> Result<()>
    where
        PgFut: std::future::Future<Output = Result<()>>,
        Neo4jFut: std::future::Future<Output = Result<()>>,
        RollbackFut: std::future::Future<Output = Result<()>>,
    {
        // Step 1: Write to PostgreSQL (source of truth) - MUST succeed
        pg_write.await.context("PostgreSQL write failed")?;

        // Step 2: Write to Neo4j (best effort)
        if let Err(e) = neo4j_write.await {
            error!("Neo4j {} failed for {}: {}", operation, edge_desc, e);
            tracing::warn!("neo4j_write_failure{{operation=\"{}\"}}", operation);

            if self.strict_mode {
                warn!("Strict mode: attempting rollback due to Neo4j failure");
                if let Some(rollback) = pg_rollback {
                    if let Err(rollback_err) = rollback.await {
                        error!(
                            "CRITICAL: Neo4j {} failed AND PostgreSQL rollback failed. Data inconsistency: {}. Rollback error: {}",
                            operation, edge_desc, rollback_err
                        );
                    }
                }
                return Err(e);
            } else {
                warn!(
                    "Non-strict mode: PostgreSQL {} succeeded but Neo4j failed (data drift possible for {})",
                    operation, edge_desc
                );
            }
        }

        Ok(())
    }

    /// Create follow with dual-write
    pub async fn create_follow(&self, follower_id: Uuid, followee_id: Uuid) -> Result<()> {
        self.execute_dual_write(
            "create_follow",
            format!("FOLLOWS {} -> {}", follower_id, followee_id),
            self.postgres.create_follow(follower_id, followee_id),
            self.neo4j.create_follow(follower_id, followee_id),
            Some(self.postgres.delete_follow(follower_id, followee_id)),
        )
        .await
    }

    /// Delete follow with dual-write
    pub async fn delete_follow(&self, follower_id: Uuid, followee_id: Uuid) -> Result<()> {
        self.execute_dual_write::<_, _, std::future::Ready<Result<()>>>(
            "delete_follow",
            format!("FOLLOWS {} -> {}", follower_id, followee_id),
            self.postgres.delete_follow(follower_id, followee_id),
            self.neo4j.delete_follow(follower_id, followee_id),
            None, // No rollback for delete operations
        )
        .await
    }

    /// Create mute with dual-write
    pub async fn create_mute(&self, muter_id: Uuid, mutee_id: Uuid) -> Result<()> {
        self.execute_dual_write(
            "create_mute",
            format!("MUTES {} -> {}", muter_id, mutee_id),
            self.postgres.create_mute(muter_id, mutee_id),
            self.neo4j.create_mute(muter_id, mutee_id),
            Some(self.postgres.delete_mute(muter_id, mutee_id)),
        )
        .await
    }

    /// Delete mute with dual-write
    pub async fn delete_mute(&self, muter_id: Uuid, mutee_id: Uuid) -> Result<()> {
        self.execute_dual_write::<_, _, std::future::Ready<Result<()>>>(
            "delete_mute",
            format!("MUTES {} -> {}", muter_id, mutee_id),
            self.postgres.delete_mute(muter_id, mutee_id),
            self.neo4j.delete_mute(muter_id, mutee_id),
            None, // No rollback for delete operations
        )
        .await
    }

    /// Create block with dual-write
    pub async fn create_block(&self, blocker_id: Uuid, blocked_id: Uuid) -> Result<()> {
        self.execute_dual_write(
            "create_block",
            format!("BLOCKS {} -> {}", blocker_id, blocked_id),
            self.postgres.create_block(blocker_id, blocked_id),
            self.neo4j.create_block(blocker_id, blocked_id),
            Some(self.postgres.delete_block(blocker_id, blocked_id)),
        )
        .await
    }

    /// Delete block with dual-write
    pub async fn delete_block(&self, blocker_id: Uuid, blocked_id: Uuid) -> Result<()> {
        self.execute_dual_write::<_, _, std::future::Ready<Result<()>>>(
            "delete_block",
            format!("BLOCKS {} -> {}", blocker_id, blocked_id),
            self.postgres.delete_block(blocker_id, blocked_id),
            self.neo4j.delete_block(blocker_id, blocked_id),
            None, // No rollback for delete operations
        )
        .await
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
                tracing::debug!(
                    "neo4j_query_success{{operation=\"get_followers\",duration_ms={}}}",
                    duration.as_millis()
                );
                Ok(result)
            }
            Err(e) => {
                error!(
                    "Neo4j get_followers failed, falling back to PostgreSQL: {}",
                    e
                );
                tracing::warn!("neo4j_query_failure{{operation=\"get_followers\"}}");

                let result = self.postgres.get_followers(user_id, limit, offset).await?;
                tracing::warn!("postgres_query_fallback{{operation=\"get_followers\"}}");
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
                tracing::debug!(
                    "neo4j_query_success{{operation=\"get_following\",duration_ms={}}}",
                    duration.as_millis()
                );
                Ok(result)
            }
            Err(e) => {
                error!(
                    "Neo4j get_following failed, falling back to PostgreSQL: {}",
                    e
                );
                tracing::warn!("neo4j_query_failure{{operation=\"get_following\"}}");

                let result = self.postgres.get_following(user_id, limit, offset).await?;
                tracing::warn!("postgres_query_fallback{{operation=\"get_following\"}}");
                Ok(result)
            }
        }
    }

    /// Check if following (Neo4j first, PostgreSQL fallback)
    pub async fn is_following(&self, follower_id: Uuid, followee_id: Uuid) -> Result<bool> {
        match self.neo4j.is_following(follower_id, followee_id).await {
            Ok(result) => {
                tracing::debug!("neo4j_query_success{{operation=\"is_following\"}}");
                Ok(result)
            }
            Err(e) => {
                error!(
                    "Neo4j is_following failed, falling back to PostgreSQL: {}",
                    e
                );
                tracing::warn!("neo4j_query_failure{{operation=\"is_following\"}}");

                let result = self.postgres.is_following(follower_id, followee_id).await?;
                tracing::warn!("postgres_query_fallback{{operation=\"is_following\"}}");
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
    #[allow(dead_code)] // Reserved for graph analytics endpoint
    pub async fn get_graph_stats(&self, user_id: Uuid) -> Result<GraphStats> {
        self.neo4j.get_graph_stats(user_id).await
    }

    /// Get blocked users (Neo4j first, PostgreSQL fallback)
    pub async fn get_blocked_users(
        &self,
        user_id: Uuid,
        limit: i32,
        offset: i32,
    ) -> Result<(Vec<Uuid>, i32, bool)> {
        let start = std::time::Instant::now();

        match self.neo4j.get_blocked_users(user_id, limit, offset).await {
            Ok(result) => {
                let duration = start.elapsed();
                tracing::debug!(
                    "neo4j_query_success{{operation=\"get_blocked_users\",duration_ms={}}}",
                    duration.as_millis()
                );
                Ok(result)
            }
            Err(e) => {
                error!(
                    "Neo4j get_blocked_users failed, falling back to PostgreSQL: {}",
                    e
                );
                tracing::warn!("neo4j_query_failure{{operation=\"get_blocked_users\"}}");

                let result = self.postgres.get_blocked_users(user_id, limit, offset).await?;
                tracing::warn!("postgres_query_fallback{{operation=\"get_blocked_users\"}}");
                Ok(result)
            }
        }
    }
}

// Implement GraphRepositoryTrait for DualWriteRepository
#[async_trait::async_trait]
impl GraphRepositoryTrait for DualWriteRepository {
    async fn create_follow(&self, follower_id: Uuid, followee_id: Uuid) -> Result<()> {
        Self::create_follow(self, follower_id, followee_id).await
    }

    async fn delete_follow(&self, follower_id: Uuid, followee_id: Uuid) -> Result<()> {
        Self::delete_follow(self, follower_id, followee_id).await
    }

    async fn create_mute(&self, muter_id: Uuid, mutee_id: Uuid) -> Result<()> {
        Self::create_mute(self, muter_id, mutee_id).await
    }

    async fn delete_mute(&self, muter_id: Uuid, mutee_id: Uuid) -> Result<()> {
        Self::delete_mute(self, muter_id, mutee_id).await
    }

    async fn create_block(&self, blocker_id: Uuid, blocked_id: Uuid) -> Result<()> {
        Self::create_block(self, blocker_id, blocked_id).await
    }

    async fn delete_block(&self, blocker_id: Uuid, blocked_id: Uuid) -> Result<()> {
        Self::delete_block(self, blocker_id, blocked_id).await
    }

    async fn get_followers(
        &self,
        user_id: Uuid,
        limit: i32,
        offset: i32,
    ) -> Result<(Vec<Uuid>, i32, bool)> {
        Self::get_followers(self, user_id, limit, offset).await
    }

    async fn get_following(
        &self,
        user_id: Uuid,
        limit: i32,
        offset: i32,
    ) -> Result<(Vec<Uuid>, i32, bool)> {
        Self::get_following(self, user_id, limit, offset).await
    }

    async fn is_following(&self, follower_id: Uuid, followee_id: Uuid) -> Result<bool> {
        Self::is_following(self, follower_id, followee_id).await
    }

    async fn is_muted(&self, muter_id: Uuid, mutee_id: Uuid) -> Result<bool> {
        Self::is_muted(self, muter_id, mutee_id).await
    }

    async fn is_blocked(&self, blocker_id: Uuid, blocked_id: Uuid) -> Result<bool> {
        Self::is_blocked(self, blocker_id, blocked_id).await
    }

    async fn batch_check_following(
        &self,
        follower_id: Uuid,
        followee_ids: Vec<Uuid>,
    ) -> Result<std::collections::HashMap<String, bool>> {
        Self::batch_check_following(self, follower_id, followee_ids).await
    }

    async fn get_blocked_users(
        &self,
        user_id: Uuid,
        limit: i32,
        offset: i32,
    ) -> Result<(Vec<Uuid>, i32, bool)> {
        Self::get_blocked_users(self, user_id, limit, offset).await
    }

    async fn health_check(&self) -> Result<()> {
        let (pg_healthy, neo4j_healthy) = Self::health_check(self).await?;
        if !pg_healthy {
            anyhow::bail!("PostgreSQL health check failed");
        }
        if !neo4j_healthy {
            warn!("Neo4j health check failed (will fallback to PostgreSQL)");
        }
        Ok(())
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
