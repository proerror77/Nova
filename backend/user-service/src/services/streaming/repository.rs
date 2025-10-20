//! Database repository for live streaming
//!
//! All PostgreSQL queries for stream management.
//! This layer is pure data access, no business logic.

use super::models::{
    CreatorInfo, StreamCategory, StreamDetails, StreamRow, StreamStatus, StreamSummary,
};
use anyhow::{Context, Result};
use chrono::{DateTime, Utc};
use sqlx::PgPool;
use uuid::Uuid;

/// Repository for stream database operations
#[derive(Clone)]
pub struct StreamRepository {
    pool: PgPool,
}

impl StreamRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    // =========================================================================
    // Create Operations
    // =========================================================================

    /// Create new stream record
    pub async fn create_stream(
        &self,
        creator_id: Uuid,
        title: String,
        description: Option<String>,
        category: Option<StreamCategory>,
        stream_key: String,
        rtmp_url: String,
    ) -> Result<StreamRow> {
        let row = sqlx::query_as!(
            StreamRow,
            r#"
            INSERT INTO live_streams (
                creator_id, title, description, category, stream_key, rtmp_url, status
            )
            VALUES ($1, $2, $3, $4, $5, $6, 'preparing')
            RETURNING
                id, creator_id, stream_key, title, description,
                category as "category: StreamCategory",
                status as "status: StreamStatus",
                rtmp_url, hls_url, thumbnail_url,
                current_viewers, peak_viewers, total_unique_viewers, total_messages,
                auto_archive, created_at, started_at, ended_at
            "#,
            creator_id,
            title,
            description,
            category as Option<StreamCategory>,
            stream_key,
            rtmp_url
        )
        .fetch_one(&self.pool)
        .await
        .context("Failed to insert stream")?;

        Ok(row)
    }

    // =========================================================================
    // Read Operations
    // =========================================================================

    /// Get stream by ID
    pub async fn get_stream_by_id(&self, stream_id: Uuid) -> Result<Option<StreamRow>> {
        let row = sqlx::query_as!(
            StreamRow,
            r#"
            SELECT
                id, creator_id, stream_key, title, description,
                category as "category: StreamCategory",
                status as "status: StreamStatus",
                rtmp_url, hls_url, thumbnail_url,
                current_viewers, peak_viewers, total_unique_viewers, total_messages,
                auto_archive, created_at, started_at, ended_at
            FROM live_streams
            WHERE id = $1
            "#,
            stream_id
        )
        .fetch_optional(&self.pool)
        .await
        .context("Failed to fetch stream by ID")?;

        Ok(row)
    }

    /// Get stream by stream key (for RTMP auth)
    pub async fn get_stream_by_key(&self, stream_key: &str) -> Result<Option<StreamRow>> {
        let row = sqlx::query_as!(
            StreamRow,
            r#"
            SELECT
                id, creator_id, stream_key, title, description,
                category as "category: StreamCategory",
                status as "status: StreamStatus",
                rtmp_url, hls_url, thumbnail_url,
                current_viewers, peak_viewers, total_unique_viewers, total_messages,
                auto_archive, created_at, started_at, ended_at
            FROM live_streams
            WHERE stream_key = $1
            "#,
            stream_key
        )
        .fetch_optional(&self.pool)
        .await
        .context("Failed to fetch stream by key")?;

        Ok(row)
    }

    /// Get creator information
    pub async fn get_creator_info(&self, user_id: Uuid) -> Result<Option<CreatorInfo>> {
        let row = sqlx::query_as!(
            CreatorInfo,
            r#"
            SELECT id, username, avatar_url
            FROM users
            WHERE id = $1
            "#,
            user_id
        )
        .fetch_optional(&self.pool)
        .await
        .context("Failed to fetch creator info")?;

        Ok(row)
    }

    /// List live streams (for discovery)
    pub async fn list_live_streams(
        &self,
        category: Option<StreamCategory>,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<StreamRow>> {
        let rows = if let Some(cat) = category {
            sqlx::query_as!(
                StreamRow,
                r#"
                SELECT
                    id, creator_id, stream_key, title, description,
                    category as "category: StreamCategory",
                    status as "status: StreamStatus",
                    rtmp_url, hls_url, thumbnail_url,
                    current_viewers, peak_viewers, total_unique_viewers, total_messages,
                    auto_archive, created_at, started_at, ended_at
                FROM live_streams
                WHERE status = 'live' AND category = $1
                ORDER BY current_viewers DESC, started_at DESC
                LIMIT $2 OFFSET $3
                "#,
                cat as StreamCategory,
                limit,
                offset
            )
            .fetch_all(&self.pool)
            .await?
        } else {
            sqlx::query_as!(
                StreamRow,
                r#"
                SELECT
                    id, creator_id, stream_key, title, description,
                    category as "category: StreamCategory",
                    status as "status: StreamStatus",
                    rtmp_url, hls_url, thumbnail_url,
                    current_viewers, peak_viewers, total_unique_viewers, total_messages,
                    auto_archive, created_at, started_at, ended_at
                FROM live_streams
                WHERE status = 'live'
                ORDER BY current_viewers DESC, started_at DESC
                LIMIT $1 OFFSET $2
                "#,
                limit,
                offset
            )
            .fetch_all(&self.pool)
            .await?
        };

        Ok(rows)
    }

    /// Count live streams
    pub async fn count_live_streams(&self, category: Option<StreamCategory>) -> Result<i64> {
        let count = if let Some(cat) = category {
            sqlx::query_scalar!(
                r#"
                SELECT COUNT(*) as "count!"
                FROM live_streams
                WHERE status = 'live' AND category = $1
                "#,
                cat as StreamCategory
            )
            .fetch_one(&self.pool)
            .await?
        } else {
            sqlx::query_scalar!(
                r#"
                SELECT COUNT(*) as "count!"
                FROM live_streams
                WHERE status = 'live'
                "#
            )
            .fetch_one(&self.pool)
            .await?
        };

        Ok(count)
    }

    // =========================================================================
    // Update Operations
    // =========================================================================

    /// Update stream status to 'live' (when RTMP connects)
    pub async fn start_stream(&self, stream_id: Uuid, hls_url: String) -> Result<()> {
        sqlx::query!(
            r#"
            UPDATE live_streams
            SET status = 'live', hls_url = $2, started_at = NOW()
            WHERE id = $1
            "#,
            stream_id,
            hls_url
        )
        .execute(&self.pool)
        .await
        .context("Failed to update stream status to live")?;

        Ok(())
    }

    /// Update stream status to 'ended' (when RTMP disconnects)
    pub async fn end_stream(&self, stream_id: Uuid) -> Result<()> {
        sqlx::query!(
            r#"
            UPDATE live_streams
            SET status = 'ended', hls_url = NULL, ended_at = NOW()
            WHERE id = $1
            "#,
            stream_id
        )
        .execute(&self.pool)
        .await
        .context("Failed to update stream status to ended")?;

        Ok(())
    }

    /// Update viewer counts (periodically synced from Redis)
    pub async fn update_viewer_counts(
        &self,
        stream_id: Uuid,
        current_viewers: i32,
        peak_viewers: i32,
    ) -> Result<()> {
        sqlx::query!(
            r#"
            UPDATE live_streams
            SET current_viewers = $2, peak_viewers = GREATEST(peak_viewers, $3)
            WHERE id = $1
            "#,
            stream_id,
            current_viewers,
            peak_viewers
        )
        .execute(&self.pool)
        .await
        .context("Failed to update viewer counts")?;

        Ok(())
    }

    /// Check if creator has an active stream
    pub async fn has_active_stream(&self, creator_id: Uuid) -> Result<bool> {
        let count = sqlx::query_scalar!(
            r#"
            SELECT COUNT(*) as "count!"
            FROM live_streams
            WHERE creator_id = $1 AND status IN ('preparing', 'live')
            "#,
            creator_id
        )
        .fetch_one(&self.pool)
        .await?;

        Ok(count > 0)
    }

    // =========================================================================
    // Delete Operations
    // =========================================================================

    /// Delete stream (creator only, requires authorization check in service layer)
    pub async fn delete_stream(&self, stream_id: Uuid) -> Result<()> {
        sqlx::query!(
            r#"
            DELETE FROM live_streams
            WHERE id = $1
            "#,
            stream_id
        )
        .execute(&self.pool)
        .await
        .context("Failed to delete stream")?;

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Integration tests require database connection
    // Run with: cargo test --test '*' -- --ignored

    #[ignore]
    #[tokio::test]
    async fn test_create_stream() {
        // TODO: Setup test database
        // let pool = PgPool::connect("postgresql://...").await.unwrap();
        // let repo = StreamRepository::new(pool);
        // let stream = repo.create_stream(...).await.unwrap();
        // assert_eq!(stream.status, StreamStatus::Preparing);
    }
}
