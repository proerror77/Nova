use anyhow::{Context, Result};
use redis::{aio::ConnectionManager, AsyncCommands};
use sqlx::PgPool;
use std::collections::HashMap;
use uuid::Uuid;

/// Redis counter service for fast reads (<10ms latency)
///
/// Keys: post:{post_id}:likes, post:{post_id}:comments, post:{post_id}:shares
/// TTL: 7 days (604800 seconds)
///
/// Architecture:
/// - Increment/Decrement: Update Redis after PostgreSQL operation
/// - Get: Read from Redis with PostgreSQL fallback
/// - Batch operations: Use Redis MGET for optimization
/// - Reconciliation: Periodic sync from PostgreSQL to Redis
#[derive(Clone)]
pub struct CounterService {
    redis: ConnectionManager,
    pg_pool: PgPool,
}

#[allow(dead_code)]
impl CounterService {
    /// TTL for counter keys (7 days) - for set_ex (u64)
    const COUNTER_TTL_U64: u64 = 604800;
    /// TTL for counter keys (7 days) - for expire (i64)
    const COUNTER_TTL_I64: i64 = 604800;

    pub fn new(redis: ConnectionManager, pg_pool: PgPool) -> Self {
        Self { redis, pg_pool }
    }

    // ========== Like Counter Operations ==========

    /// Increment like count (called after PostgreSQL insert)
    pub async fn increment_like_count(&self, post_id: Uuid) -> Result<i64> {
        let key = format!("post:{}:likes", post_id);
        let new_count: i64 = self
            .redis
            .clone()
            .incr(&key, 1)
            .await
            .context("Failed to increment like count")?;

        // Set TTL on first increment
        if new_count == 1 {
            let _: () = self
                .redis
                .clone()
                .expire(&key, Self::COUNTER_TTL_I64)
                .await
                .context("Failed to set TTL on like counter")?;
        }

        Ok(new_count)
    }

    /// Decrement like count (called after PostgreSQL delete)
    pub async fn decrement_like_count(&self, post_id: Uuid) -> Result<i64> {
        let key = format!("post:{}:likes", post_id);

        // Ensure counter doesn't go negative
        let current: i64 = self.redis.clone().get(&key).await.unwrap_or(0);

        if current > 0 {
            let new_count: i64 = self
                .redis
                .clone()
                .decr(&key, 1)
                .await
                .context("Failed to decrement like count")?;
            Ok(new_count)
        } else {
            Ok(0)
        }
    }

    /// Get like count (with PostgreSQL fallback)
    pub async fn get_like_count(&self, post_id: Uuid) -> Result<i64> {
        let key = format!("post:{}:likes", post_id);

        // Try Redis first
        let count: Option<i64> = self
            .redis
            .clone()
            .get(&key)
            .await
            .context("Failed to get like count from Redis")?;

        match count {
            Some(count) => Ok(count),
            None => {
                // Redis miss: load from PostgreSQL and warm cache
                let count = self.load_like_count_from_pg(post_id).await?;
                let _: () = self
                    .redis
                    .clone()
                    .set_ex(&key, count, Self::COUNTER_TTL_U64)
                    .await
                    .context("Failed to warm like count cache")?;
                Ok(count)
            }
        }
    }

    // ========== Comment Counter Operations ==========

    /// Increment comment count
    pub async fn increment_comment_count(&self, post_id: Uuid) -> Result<i64> {
        let key = format!("post:{}:comments", post_id);
        let new_count: i64 = self
            .redis
            .clone()
            .incr(&key, 1)
            .await
            .context("Failed to increment comment count")?;

        if new_count == 1 {
            let _: () = self
                .redis
                .clone()
                .expire(&key, Self::COUNTER_TTL_I64)
                .await
                .context("Failed to set TTL on comment counter")?;
        }

        Ok(new_count)
    }

    /// Decrement comment count (soft delete)
    pub async fn decrement_comment_count(&self, post_id: Uuid) -> Result<i64> {
        let key = format!("post:{}:comments", post_id);

        let current: i64 = self.redis.clone().get(&key).await.unwrap_or(0);

        if current > 0 {
            let new_count: i64 = self
                .redis
                .clone()
                .decr(&key, 1)
                .await
                .context("Failed to decrement comment count")?;
            Ok(new_count)
        } else {
            Ok(0)
        }
    }

    /// Get comment count
    pub async fn get_comment_count(&self, post_id: Uuid) -> Result<i64> {
        let key = format!("post:{}:comments", post_id);

        let count: Option<i64> = self
            .redis
            .clone()
            .get(&key)
            .await
            .context("Failed to get comment count from Redis")?;

        match count {
            Some(count) => Ok(count),
            None => {
                let count = self.load_comment_count_from_pg(post_id).await?;
                let _: () = self
                    .redis
                    .clone()
                    .set_ex(&key, count, Self::COUNTER_TTL_U64)
                    .await
                    .context("Failed to warm comment count cache")?;
                Ok(count)
            }
        }
    }

    // ========== Share Counter Operations ==========

    /// Increment share count
    pub async fn increment_share_count(&self, post_id: Uuid) -> Result<i64> {
        let key = format!("post:{}:shares", post_id);
        let new_count: i64 = self
            .redis
            .clone()
            .incr(&key, 1)
            .await
            .context("Failed to increment share count")?;

        if new_count == 1 {
            let _: () = self
                .redis
                .clone()
                .expire(&key, Self::COUNTER_TTL_I64)
                .await
                .context("Failed to set TTL on share counter")?;
        }

        Ok(new_count)
    }

    /// Get share count
    pub async fn get_share_count(&self, post_id: Uuid) -> Result<i64> {
        let key = format!("post:{}:shares", post_id);

        let count: Option<i64> = self
            .redis
            .clone()
            .get(&key)
            .await
            .context("Failed to get share count from Redis")?;

        match count {
            Some(count) => Ok(count),
            None => {
                let count = self.load_share_count_from_pg(post_id).await?;
                let _: () = self
                    .redis
                    .clone()
                    .set_ex(&key, count, Self::COUNTER_TTL_U64)
                    .await
                    .context("Failed to warm share count cache")?;
                Ok(count)
            }
        }
    }

    // ========== Batch Operations (MGET Optimization) ==========

    /// Batch get all counts for multiple posts (optimized with Redis MGET)
    /// Falls back to PostgreSQL if Redis is unavailable
    pub async fn batch_get_counts(&self, post_ids: &[Uuid]) -> Result<HashMap<Uuid, PostCounts>> {
        if post_ids.is_empty() {
            return Ok(HashMap::new());
        }

        // Build keys for MGET: [likes1, comments1, shares1, likes2, comments2, shares2, ...]
        let mut keys = Vec::new();
        for post_id in post_ids {
            keys.push(format!("post:{}:likes", post_id));
            keys.push(format!("post:{}:comments", post_id));
            keys.push(format!("post:{}:shares", post_id));
        }

        // Try Redis first, fallback to PostgreSQL on error
        let redis_result: std::result::Result<Vec<Option<i64>>, _> = self
            .redis
            .clone()
            .get(&keys)
            .await;

        let result = match redis_result {
            Ok(values) => {
                // Redis succeeded - parse results
                let bookmark_counts = self.batch_get_bookmark_counts_from_pg(post_ids).await?;
                let mut result = HashMap::new();
                for (i, post_id) in post_ids.iter().enumerate() {
                    let like_count = values[i * 3].unwrap_or(0);
                    let comment_count = values[i * 3 + 1].unwrap_or(0);
                    let share_count = values[i * 3 + 2].unwrap_or(0);
                    let bookmark_count = bookmark_counts.get(post_id).copied().unwrap_or(0);

                    result.insert(
                        *post_id,
                        PostCounts {
                            like_count,
                            comment_count,
                            share_count,
                            bookmark_count,
                        },
                    );
                }

                // Warm cache for missing entries (async background job)
                if let Err(err) = self.warm_missing_counters(post_ids, &result).await {
                    tracing::warn!(
                        error = ?err,
                        post_count = post_ids.len(),
                        "Failed to warm missing counters"
                    );
                }

                result
            }
            Err(redis_err) => {
                // Redis failed - fallback to PostgreSQL
                tracing::warn!(
                    error = ?redis_err,
                    post_count = post_ids.len(),
                    "Redis MGET failed, falling back to PostgreSQL"
                );
                self.load_counters_from_pg(post_ids).await?
            }
        };

        Ok(result)
    }

    /// Batch get bookmark counts from PostgreSQL
    async fn batch_get_bookmark_counts_from_pg(
        &self,
        post_ids: &[Uuid],
    ) -> Result<HashMap<Uuid, i64>> {
        if post_ids.is_empty() {
            return Ok(HashMap::new());
        }

        let rows: Vec<(Uuid, i64)> = sqlx::query_as(
            r#"
            SELECT post_id, COUNT(*) as count
            FROM saved_posts
            WHERE post_id = ANY($1)
            GROUP BY post_id
            "#,
        )
        .bind(post_ids)
        .fetch_all(&self.pg_pool)
        .await
        .context("Failed to fetch bookmark counts from PostgreSQL")?;

        let mut result: HashMap<Uuid, i64> = HashMap::new();
        for (post_id, count) in rows {
            result.insert(post_id, count);
        }

        Ok(result)
    }

    /// Warm Redis cache from PostgreSQL for posts with missing counters
    async fn warm_missing_counters(
        &self,
        post_ids: &[Uuid],
        current_cache: &HashMap<Uuid, PostCounts>,
    ) -> Result<()> {
        // Identify posts with all zeros (likely cache miss)
        let missing_posts: Vec<Uuid> = post_ids
            .iter()
            .filter(|id| {
                current_cache
                    .get(id)
                    .map(|c| c.like_count == 0 && c.comment_count == 0 && c.share_count == 0)
                    .unwrap_or(true)
            })
            .copied()
            .collect();

        if missing_posts.is_empty() {
            return Ok(());
        }

        // Load from PostgreSQL
        let pg_counters = self.load_counters_from_pg(&missing_posts).await?;

        // Warm Redis cache using pipeline
        let mut pipe = redis::pipe();
        for (post_id, counts) in pg_counters {
            pipe.set_ex(
                format!("post:{}:likes", post_id),
                counts.like_count,
                Self::COUNTER_TTL_U64,
            )
            .ignore();
            pipe.set_ex(
                format!("post:{}:comments", post_id),
                counts.comment_count,
                Self::COUNTER_TTL_U64,
            )
            .ignore();
            pipe.set_ex(
                format!("post:{}:shares", post_id),
                counts.share_count,
                Self::COUNTER_TTL_U64,
            )
            .ignore();
        }

        pipe.query_async::<_, ()>(&mut self.redis.clone())
            .await
            .context("Failed to warm counters in Redis")?;

        Ok(())
    }

    // ========== PostgreSQL Fallback Operations ==========

    /// Load like count from PostgreSQL
    async fn load_like_count_from_pg(&self, post_id: Uuid) -> Result<i64> {
        let count: Option<i64> =
            sqlx::query_scalar("SELECT like_count FROM post_counters WHERE post_id = $1")
                .bind(post_id)
                .fetch_optional(&self.pg_pool)
                .await
                .context("Failed to load like count from PostgreSQL")?;

        Ok(count.unwrap_or(0))
    }

    /// Load comment count from PostgreSQL
    async fn load_comment_count_from_pg(&self, post_id: Uuid) -> Result<i64> {
        let count: Option<i64> =
            sqlx::query_scalar("SELECT comment_count FROM post_counters WHERE post_id = $1")
                .bind(post_id)
                .fetch_optional(&self.pg_pool)
                .await
                .context("Failed to load comment count from PostgreSQL")?;

        Ok(count.unwrap_or(0))
    }

    /// Load share count from PostgreSQL
    async fn load_share_count_from_pg(&self, post_id: Uuid) -> Result<i64> {
        let count: Option<i64> =
            sqlx::query_scalar("SELECT share_count FROM post_counters WHERE post_id = $1")
                .bind(post_id)
                .fetch_optional(&self.pg_pool)
                .await
                .context("Failed to load share count from PostgreSQL")?;

        Ok(count.unwrap_or(0))
    }

    /// Batch load counters from PostgreSQL
    async fn load_counters_from_pg(&self, post_ids: &[Uuid]) -> Result<HashMap<Uuid, PostCounts>> {
        let rows = sqlx::query_as::<_, (Uuid, i64, i64, i64)>(
            "SELECT post_id, like_count, comment_count, share_count
             FROM post_counters
             WHERE post_id = ANY($1)",
        )
        .bind(post_ids)
        .fetch_all(&self.pg_pool)
        .await
        .context("Failed to batch load counters from PostgreSQL")?;

        let mut result = HashMap::new();
        for (post_id, like_count, comment_count, share_count) in rows {
            result.insert(
                post_id,
                PostCounts {
                    like_count,
                    comment_count,
                    share_count,
                    bookmark_count: 0, // Bookmark counts fetched separately
                },
            );
        }

        Ok(result)
    }

    // ========== Reconciliation (Cron Job) ==========

    /// Reconciliation: sync PostgreSQL counters to Redis (cron job)
    ///
    /// This should be called periodically to ensure Redis cache consistency
    /// with PostgreSQL source of truth.
    pub async fn reconcile_counters(&self, post_ids: &[Uuid]) -> Result<usize> {
        if post_ids.is_empty() {
            return Ok(0);
        }

        let pg_counters = self.load_counters_from_pg(post_ids).await?;

        let mut pipe = redis::pipe();
        for (post_id, counts) in &pg_counters {
            pipe.set_ex(
                format!("post:{}:likes", post_id),
                counts.like_count,
                Self::COUNTER_TTL_U64,
            )
            .ignore();
            pipe.set_ex(
                format!("post:{}:comments", post_id),
                counts.comment_count,
                Self::COUNTER_TTL_U64,
            )
            .ignore();
            pipe.set_ex(
                format!("post:{}:shares", post_id),
                counts.share_count,
                Self::COUNTER_TTL_U64,
            )
            .ignore();
        }

        pipe.query_async::<_, ()>(&mut self.redis.clone())
            .await
            .context("Failed to reconcile counters in Redis")?;

        tracing::info!(
            reconciled_count = pg_counters.len(),
            "Reconciled counters from PostgreSQL to Redis"
        );

        Ok(pg_counters.len())
    }

    // ========== Legacy API Support (for backward compatibility) ==========

    /// Set like count for a post (used for cache warming)
    pub async fn set_like_count(&self, post_id: Uuid, count: i64) -> Result<()> {
        let key = format!("post:{}:likes", post_id);
        let _: () = self
            .redis
            .clone()
            .set_ex(&key, count, Self::COUNTER_TTL_U64)
            .await
            .context("Failed to set like count")?;
        Ok(())
    }

    /// Set comment count for a post (used for cache warming)
    pub async fn set_comment_count(&self, post_id: Uuid, count: i64) -> Result<()> {
        let key = format!("post:{}:comments", post_id);
        let _: () = self
            .redis
            .clone()
            .set_ex(&key, count, Self::COUNTER_TTL_U64)
            .await
            .context("Failed to set comment count")?;
        Ok(())
    }

    /// Set share count for a post (used for cache warming)
    pub async fn set_share_count(&self, post_id: Uuid, count: i64) -> Result<()> {
        let key = format!("post:{}:shares", post_id);
        let _: () = self
            .redis
            .clone()
            .set_ex(&key, count, Self::COUNTER_TTL_U64)
            .await
            .context("Failed to set share count")?;
        Ok(())
    }

    /// Batch get all stats for multiple posts (legacy API)
    pub async fn batch_get_post_stats(
        &self,
        post_ids: &[Uuid],
    ) -> Result<HashMap<Uuid, (i64, i64, i64)>> {
        let counts = self.batch_get_counts(post_ids).await?;
        let mut result = HashMap::new();

        for (post_id, post_counts) in counts {
            result.insert(
                post_id,
                (
                    post_counts.like_count,
                    post_counts.comment_count,
                    post_counts.share_count,
                ),
            );
        }

        Ok(result)
    }
}

/// Post counter statistics
#[allow(dead_code)]
#[derive(Debug, Clone)]
pub struct PostCounts {
    pub like_count: i64,
    pub comment_count: i64,
    pub share_count: i64,
    pub bookmark_count: i64,
}
