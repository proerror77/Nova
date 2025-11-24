use anyhow::{Context, Result};
use chrono::{DateTime, Utc};
use neo4rs::{query, Graph};
use sqlx::PgPool;
use std::sync::Arc;
use tracing::{error, info, warn};
use uuid::Uuid;

/// Neo4j backfill orchestrator
pub struct Neo4jBackfill {
    pg_pool: PgPool,
    neo4j_graph: Arc<Graph>,
}

impl Neo4jBackfill {
    pub fn new(pg_pool: PgPool, neo4j_graph: Arc<Graph>) -> Self {
        Self {
            pg_pool,
            neo4j_graph,
        }
    }

    /// Run full backfill from PostgreSQL to Neo4j
    pub async fn run(&self) -> Result<BackfillStats> {
        info!("Starting Neo4j backfill from PostgreSQL");

        let mut stats = BackfillStats::default();

        // Step 1: Migrate users
        stats.users_migrated = self.backfill_users().await?;

        // Step 2: Migrate follow relationships
        stats.follows_migrated = self.backfill_follows().await?;

        // Step 3: Migrate mutes (if exists)
        stats.mutes_migrated = self.backfill_mutes().await.unwrap_or(0);

        // Step 4: Migrate blocks (if exists)
        stats.blocks_migrated = self.backfill_blocks().await.unwrap_or(0);

        // Step 5: Verify consistency
        self.verify_consistency(&stats).await?;

        info!(
            "Neo4j backfill completed: {} users, {} follows, {} mutes, {} blocks",
            stats.users_migrated, stats.follows_migrated, stats.mutes_migrated, stats.blocks_migrated
        );

        Ok(stats)
    }

    /// Migrate all active users to Neo4j
    async fn backfill_users(&self) -> Result<u64> {
        info!("Migrating users from PostgreSQL to Neo4j");

        let users = sqlx::query_as::<_, (Uuid, String, DateTime<Utc>)>(
            "SELECT id, username, created_at FROM users WHERE deleted_at IS NULL ORDER BY created_at"
        )
        .fetch_all(&self.pg_pool)
        .await
        .context("Failed to fetch users from PostgreSQL")?;

        let total_users = users.len();
        info!("Found {} active users to migrate", total_users);

        let mut migrated = 0u64;
        let batch_size = 1000;

        for (i, chunk) in users.chunks(batch_size).enumerate() {
            let mut batch_query = String::from("UNWIND $batch AS user\n");
            batch_query.push_str("MERGE (u:User {id: user.id})\n");
            batch_query.push_str("SET u.username = user.username, u.created_at = user.created_at\n");
            batch_query.push_str("RETURN count(u) as migrated");

            let batch_data: Vec<serde_json::Value> = chunk
                .iter()
                .map(|(id, username, created_at)| {
                    serde_json::json!({
                        "id": id.to_string(),
                        "username": username,
                        "created_at": created_at.timestamp()
                    })
                })
                .collect();

            match self
                .neo4j_graph
                .run(query(&batch_query).param("batch", batch_data))
                .await
            {
                Ok(_) => {
                    migrated += chunk.len() as u64;
                    info!(
                        "Migrated user batch {}/{} ({} users)",
                        i + 1,
                        (total_users + batch_size - 1) / batch_size,
                        migrated
                    );
                }
                Err(e) => {
                    error!("Failed to migrate user batch {}: {}", i + 1, e);
                    return Err(e.into());
                }
            }
        }

        Ok(migrated)
    }

    /// Migrate follow relationships
    async fn backfill_follows(&self) -> Result<u64> {
        info!("Migrating follow relationships from PostgreSQL to Neo4j");

        // Note: PostgreSQL uses 'following_id', we map to 'followee_id' for Neo4j
        let follows = sqlx::query_as::<_, (Uuid, Uuid, DateTime<Utc>)>(
            "SELECT follower_id, following_id, created_at FROM follows ORDER BY created_at"
        )
        .fetch_all(&self.pg_pool)
        .await
        .context("Failed to fetch follows from PostgreSQL")?;

        let total_follows = follows.len();
        info!("Found {} follow relationships to migrate", total_follows);

        let mut migrated = 0u64;
        let batch_size = 1000;

        for (i, chunk) in follows.chunks(batch_size).enumerate() {
            let mut batch_query = String::from("UNWIND $batch AS follow\n");
            batch_query.push_str("MATCH (a:User {id: follow.follower})\n");
            batch_query.push_str("MATCH (b:User {id: follow.followee})\n");
            batch_query.push_str("MERGE (a)-[r:FOLLOWS]->(b)\n");
            batch_query.push_str("SET r.created_at = follow.created_at\n");
            batch_query.push_str("RETURN count(r) as migrated");

            let batch_data: Vec<serde_json::Value> = chunk
                .iter()
                .map(|(follower_id, following_id, created_at)| {
                    serde_json::json!({
                        "follower": follower_id.to_string(),
                        "followee": following_id.to_string(),
                        "created_at": created_at.timestamp()
                    })
                })
                .collect();

            match self
                .neo4j_graph
                .run(query(&batch_query).param("batch", batch_data))
                .await
            {
                Ok(_) => {
                    migrated += chunk.len() as u64;
                    info!(
                        "Migrated follow batch {}/{} ({} relationships)",
                        i + 1,
                        (total_follows + batch_size - 1) / batch_size,
                        migrated
                    );
                }
                Err(e) => {
                    error!("Failed to migrate follow batch {}: {}", i + 1, e);
                    return Err(e.into());
                }
            }
        }

        Ok(migrated)
    }

    /// Migrate mutes (if table exists)
    async fn backfill_mutes(&self) -> Result<u64> {
        info!("Checking for mutes table");

        // Check if mutes table exists
        let table_exists: bool = sqlx::query_scalar(
            "SELECT EXISTS (
                SELECT FROM information_schema.tables
                WHERE table_schema = 'public'
                AND table_name = 'mutes'
            )"
        )
        .fetch_one(&self.pg_pool)
        .await?;

        if !table_exists {
            warn!("Mutes table does not exist, skipping");
            return Ok(0);
        }

        let mutes = sqlx::query_as::<_, (Uuid, Uuid, DateTime<Utc>)>(
            "SELECT muter_id, muted_id, created_at FROM mutes ORDER BY created_at"
        )
        .fetch_all(&self.pg_pool)
        .await
        .context("Failed to fetch mutes from PostgreSQL")?;

        let total_mutes = mutes.len();
        info!("Found {} mute relationships to migrate", total_mutes);

        let mut migrated = 0u64;
        let batch_size = 1000;

        for (i, chunk) in mutes.chunks(batch_size).enumerate() {
            let mut batch_query = String::from("UNWIND $batch AS mute\n");
            batch_query.push_str("MATCH (a:User {id: mute.muter})\n");
            batch_query.push_str("MATCH (b:User {id: mute.muted})\n");
            batch_query.push_str("MERGE (a)-[r:MUTES]->(b)\n");
            batch_query.push_str("SET r.created_at = mute.created_at\n");
            batch_query.push_str("RETURN count(r) as migrated");

            let batch_data: Vec<serde_json::Value> = chunk
                .iter()
                .map(|(muter_id, muted_id, created_at)| {
                    serde_json::json!({
                        "muter": muter_id.to_string(),
                        "muted": muted_id.to_string(),
                        "created_at": created_at.timestamp()
                    })
                })
                .collect();

            match self
                .neo4j_graph
                .run(query(&batch_query).param("batch", batch_data))
                .await
            {
                Ok(_) => {
                    migrated += chunk.len() as u64;
                    info!(
                        "Migrated mute batch {}/{} ({} relationships)",
                        i + 1,
                        (total_mutes + batch_size - 1) / batch_size,
                        migrated
                    );
                }
                Err(e) => {
                    error!("Failed to migrate mute batch {}: {}", i + 1, e);
                    return Err(e.into());
                }
            }
        }

        Ok(migrated)
    }

    /// Migrate blocks (if table exists)
    async fn backfill_blocks(&self) -> Result<u64> {
        info!("Checking for blocks table");

        // Check if blocks table exists
        let table_exists: bool = sqlx::query_scalar(
            "SELECT EXISTS (
                SELECT FROM information_schema.tables
                WHERE table_schema = 'public'
                AND table_name = 'blocks'
            )"
        )
        .fetch_one(&self.pg_pool)
        .await?;

        if !table_exists {
            warn!("Blocks table does not exist, skipping");
            return Ok(0);
        }

        let blocks = sqlx::query_as::<_, (Uuid, Uuid, DateTime<Utc>)>(
            "SELECT blocker_id, blocked_id, created_at FROM blocks ORDER BY created_at"
        )
        .fetch_all(&self.pg_pool)
        .await
        .context("Failed to fetch blocks from PostgreSQL")?;

        let total_blocks = blocks.len();
        info!("Found {} block relationships to migrate", total_blocks);

        let mut migrated = 0u64;
        let batch_size = 1000;

        for (i, chunk) in blocks.chunks(batch_size).enumerate() {
            let mut batch_query = String::from("UNWIND $batch AS block\n");
            batch_query.push_str("MATCH (a:User {id: block.blocker})\n");
            batch_query.push_str("MATCH (b:User {id: block.blocked})\n");
            batch_query.push_str("MERGE (a)-[r:BLOCKS]->(b)\n");
            batch_query.push_str("SET r.created_at = block.created_at\n");
            batch_query.push_str("RETURN count(r) as migrated");

            let batch_data: Vec<serde_json::Value> = chunk
                .iter()
                .map(|(blocker_id, blocked_id, created_at)| {
                    serde_json::json!({
                        "blocker": blocker_id.to_string(),
                        "blocked": blocked_id.to_string(),
                        "created_at": created_at.timestamp()
                    })
                })
                .collect();

            match self
                .neo4j_graph
                .run(query(&batch_query).param("batch", batch_data))
                .await
            {
                Ok(_) => {
                    migrated += chunk.len() as u64;
                    info!(
                        "Migrated block batch {}/{} ({} relationships)",
                        i + 1,
                        (total_blocks + batch_size - 1) / batch_size,
                        migrated
                    );
                }
                Err(e) => {
                    error!("Failed to migrate block batch {}: {}", i + 1, e);
                    return Err(e.into());
                }
            }
        }

        Ok(migrated)
    }

    /// Verify data consistency between PostgreSQL and Neo4j
    async fn verify_consistency(&self, stats: &BackfillStats) -> Result<()> {
        info!("Verifying data consistency between PostgreSQL and Neo4j");

        // Verify user count
        let pg_user_count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM users WHERE deleted_at IS NULL"
        )
        .fetch_one(&self.pg_pool)
        .await?;

        let mut neo4j_result = self
            .neo4j_graph
            .execute(query("MATCH (u:User) RETURN count(u) as total"))
            .await?;

        let neo4j_user_count: i64 = if let Some(row) = neo4j_result.next().await? {
            row.get("total").unwrap_or(0)
        } else {
            0
        };

        if pg_user_count != neo4j_user_count {
            error!(
                "User count mismatch: PostgreSQL={}, Neo4j={}",
                pg_user_count, neo4j_user_count
            );
            return Err(anyhow::anyhow!(
                "User count mismatch: expected {}, got {}",
                pg_user_count,
                neo4j_user_count
            ));
        }

        info!("✅ User count verified: {}", pg_user_count);

        // Verify follow count
        let pg_follow_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM follows")
            .fetch_one(&self.pg_pool)
            .await?;

        let mut neo4j_result = self
            .neo4j_graph
            .execute(query("MATCH ()-[r:FOLLOWS]->() RETURN count(r) as total"))
            .await?;

        let neo4j_follow_count: i64 = if let Some(row) = neo4j_result.next().await? {
            row.get("total").unwrap_or(0)
        } else {
            0
        };

        if pg_follow_count != neo4j_follow_count {
            error!(
                "Follow count mismatch: PostgreSQL={}, Neo4j={}",
                pg_follow_count, neo4j_follow_count
            );
            return Err(anyhow::anyhow!(
                "Follow count mismatch: expected {}, got {}",
                pg_follow_count,
                neo4j_follow_count
            ));
        }

        info!("✅ Follow count verified: {}", pg_follow_count);

        // Sample verification: Check 10 random users
        let sample_users: Vec<(Uuid,)> = sqlx::query_as(
            "SELECT id FROM users WHERE deleted_at IS NULL ORDER BY RANDOM() LIMIT 10"
        )
        .fetch_all(&self.pg_pool)
        .await?;

        for (user_id,) in sample_users {
            let pg_follower_count: i64 = sqlx::query_scalar(
                "SELECT COUNT(*) FROM follows WHERE following_id = $1"
            )
            .bind(user_id)
            .fetch_one(&self.pg_pool)
            .await?;

            let mut neo4j_result = self
                .neo4j_graph
                .execute(
                    query("MATCH ()-[:FOLLOWS]->(u:User {id: $user_id}) RETURN count(*) as total")
                        .param("user_id", user_id.to_string()),
                )
                .await?;

            let neo4j_follower_count: i64 = if let Some(row) = neo4j_result.next().await? {
                row.get("total").unwrap_or(0)
            } else {
                0
            };

            if pg_follower_count != neo4j_follower_count {
                error!(
                    "Follower count mismatch for user {}: PostgreSQL={}, Neo4j={}",
                    user_id, pg_follower_count, neo4j_follower_count
                );
                return Err(anyhow::anyhow!(
                    "Follower count mismatch for user {}",
                    user_id
                ));
            }
        }

        info!("✅ Sample verification passed (10 users)");
        info!("✅ Consistency verification completed successfully");

        Ok(())
    }

    /// Clear all Neo4j data (for testing/rollback)
    pub async fn clear_neo4j(&self) -> Result<()> {
        warn!("⚠️  Clearing all Neo4j data");

        self.neo4j_graph
            .run(query("MATCH (n) DETACH DELETE n"))
            .await
            .context("Failed to clear Neo4j data")?;

        info!("Neo4j data cleared");
        Ok(())
    }
}

#[derive(Debug, Default)]
pub struct BackfillStats {
    pub users_migrated: u64,
    pub follows_migrated: u64,
    pub mutes_migrated: u64,
    pub blocks_migrated: u64,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    #[ignore] // Run manually: cargo test --ignored
    async fn test_backfill() {
        // Requires running PostgreSQL and Neo4j
        let database_url = std::env::var("DATABASE_URL")
            .expect("DATABASE_URL must be set");
        let neo4j_uri = std::env::var("NEO4J_URI")
            .unwrap_or_else(|_| "bolt://localhost:7687".to_string());
        let neo4j_user = std::env::var("NEO4J_USER")
            .unwrap_or_else(|_| "neo4j".to_string());
        let neo4j_password = std::env::var("NEO4J_PASSWORD")
            .unwrap_or_else(|_| "password".to_string());

        let pg_pool = PgPool::connect(&database_url).await.unwrap();
        let neo4j_graph = Graph::new(&neo4j_uri, &neo4j_user, &neo4j_password)
            .await
            .unwrap();

        let backfill = Neo4jBackfill::new(pg_pool, Arc::new(neo4j_graph));

        // Clear before test
        backfill.clear_neo4j().await.unwrap();

        // Run backfill
        let stats = backfill.run().await.unwrap();

        println!("Backfill stats: {:?}", stats);
        assert!(stats.users_migrated > 0);
    }
}
