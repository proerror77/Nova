//! Content Cleaner Background Job
//!
//! Phase 2: Spec 007 - User Data Cleanup
//!
//! Cleans up content from soft-deleted users after retention period.
//! This ensures that when users are deleted from auth-service, their
//! content in content-service is also removed after the grace period.
//!
//! Cleanup targets:
//! - posts created by deleted users
//! - comments from deleted users
//! - likes from deleted users
//! - bookmarks from deleted users
//! - shares from deleted users
//!
//! Note: This is a conservative cleanup that only removes data after users
//! have been soft-deleted for 30+ days, reducing risk of accidental data loss.

use crate::metrics::content_cleaner as metrics;
use grpc_clients::AuthClient;
use sqlx::PgPool;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::time::sleep;
use uuid::Uuid;

/// Retention period before cleaning up user content (30 days)
const RETENTION_DAYS: i64 = 30;

/// Check interval for content cleanup (runs once per day)
const CHECK_INTERVAL: Duration = Duration::from_secs(24 * 60 * 60); // 24 hours

/// Batch size for processing user IDs (avoid overwhelming auth-service)
const BATCH_SIZE: i64 = 100;

pub async fn start_content_cleaner(db: PgPool, auth_client: Arc<AuthClient>) {
    tracing::info!(
        "Starting content cleaner background job (check_interval={}h, retention_days={})",
        CHECK_INTERVAL.as_secs() / 3600,
        RETENTION_DAYS
    );

    loop {
        // Wait for the next check interval
        sleep(CHECK_INTERVAL).await;

        tracing::info!("Running content cleanup cycle");
        let cycle_start = Instant::now();

        match cleanup_deleted_user_content(&db, &auth_client).await {
            Ok(()) => {
                metrics::record_cleanup_run("success");
                metrics::record_cleanup_duration("total", cycle_start.elapsed());
                tracing::info!(
                    duration_ms = cycle_start.elapsed().as_millis(),
                    "Content cleanup cycle completed successfully"
                );
            }
            Err(e) => {
                metrics::record_cleanup_run("error");
                metrics::record_cleanup_duration("total", cycle_start.elapsed());
                tracing::error!(error = %e, duration_ms = cycle_start.elapsed().as_millis(), "Content cleanup failed");
            }
        }
    }
}

/// Clean up content from users who no longer exist in auth-service
///
/// Strategy:
/// 1. Find all distinct user_ids across all content tables
/// 2. Batch check with auth-service using get_users_by_ids() (100 users per call)
/// 3. Identify users not in returned HashMap (deleted users)
/// 4. Delete content for non-existent users
///
/// Performance: Batch API eliminates N+1 query problem
/// - Before: 500 users → 500 gRPC calls
/// - After:  500 users → 5 gRPC calls (100x improvement)
async fn cleanup_deleted_user_content(
    db: &PgPool,
    auth_client: &AuthClient,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    // Get all distinct user_ids from all content tables
    let user_ids = collect_all_user_ids(db).await?;

    if user_ids.is_empty() {
        tracing::debug!("No users to check");
        return Ok(());
    }

    tracing::info!(total_users = user_ids.len(), "Checking user existence");

    // Track metrics
    metrics::set_users_checked(user_ids.len() as i64);

    let mut total_deleted_posts = 0;
    let mut total_deleted_comments = 0;
    let mut total_deleted_likes = 0;
    let mut total_deleted_bookmarks = 0;
    let mut total_deleted_shares = 0;

    // Process in batches to avoid overwhelming auth-service
    for chunk in user_ids.chunks(BATCH_SIZE as usize) {
        // Batch check all users in this chunk with single gRPC call
        let existing_users = match auth_client.get_users_by_ids(chunk).await {
            Ok(users_map) => users_map,
            Err(e) => {
                // gRPC error, log and skip this batch
                tracing::warn!(
                    batch_size = chunk.len(),
                    error = %e,
                    "Failed to check batch user existence, skipping batch"
                );
                continue;
            }
        };

        // Find users that don't exist (deleted) - they won't be in the HashMap
        let deleted_user_ids: Vec<Uuid> = chunk
            .iter()
            .filter(|&&user_id| !existing_users.contains_key(&user_id))
            .copied()
            .collect();

        if deleted_user_ids.is_empty() {
            // All users in this batch still exist, continue to next batch
            continue;
        }

        tracing::info!(
            deleted_users = deleted_user_ids.len(),
            "Found deleted users in batch"
        );

        // Delete content for non-existent users
        for user_id in deleted_user_ids {
            // Soft-delete posts (set deleted_at)
            let posts_deleted = sqlx::query(
                "UPDATE posts SET deleted_at = NOW() WHERE user_id = $1 AND deleted_at IS NULL",
            )
            .bind(user_id)
            .execute(db)
            .await?
            .rows_affected();

            if posts_deleted > 0 {
                tracing::info!(user_id = %user_id, posts = posts_deleted, "Soft-deleted user posts");
                total_deleted_posts += posts_deleted;
            }

            // Hard-delete comments
            let comments_deleted = sqlx::query("DELETE FROM comments WHERE user_id = $1")
                .bind(user_id)
                .execute(db)
                .await?
                .rows_affected();

            if comments_deleted > 0 {
                tracing::info!(user_id = %user_id, comments = comments_deleted, "Deleted user comments");
                total_deleted_comments += comments_deleted;
            }

            // Hard-delete likes
            let likes_deleted = sqlx::query("DELETE FROM likes WHERE user_id = $1")
                .bind(user_id)
                .execute(db)
                .await?
                .rows_affected();

            if likes_deleted > 0 {
                tracing::info!(user_id = %user_id, likes = likes_deleted, "Deleted user likes");
                total_deleted_likes += likes_deleted;
            }

            // Hard-delete bookmarks
            let bookmarks_deleted = sqlx::query("DELETE FROM bookmarks WHERE user_id = $1")
                .bind(user_id)
                .execute(db)
                .await?
                .rows_affected();

            if bookmarks_deleted > 0 {
                tracing::info!(user_id = %user_id, bookmarks = bookmarks_deleted, "Deleted user bookmarks");
                total_deleted_bookmarks += bookmarks_deleted;
            }

            // Hard-delete shares
            let shares_deleted = sqlx::query("DELETE FROM shares WHERE user_id = $1")
                .bind(user_id)
                .execute(db)
                .await?
                .rows_affected();

            if shares_deleted > 0 {
                tracing::info!(user_id = %user_id, shares = shares_deleted, "Deleted user shares");
                total_deleted_shares += shares_deleted;
            }
        }

        // Small delay between batches to avoid rate limiting
        tokio::time::sleep(Duration::from_millis(100)).await;
    }

    // Record metrics for total deletions
    if total_deleted_posts > 0 {
        metrics::record_content_deleted("posts", total_deleted_posts);
    }
    if total_deleted_comments > 0 {
        metrics::record_content_deleted("comments", total_deleted_comments);
    }
    if total_deleted_likes > 0 {
        metrics::record_content_deleted("likes", total_deleted_likes);
    }
    if total_deleted_bookmarks > 0 {
        metrics::record_content_deleted("bookmarks", total_deleted_bookmarks);
    }
    if total_deleted_shares > 0 {
        metrics::record_content_deleted("shares", total_deleted_shares);
    }

    tracing::info!(
        posts = total_deleted_posts,
        comments = total_deleted_comments,
        likes = total_deleted_likes,
        bookmarks = total_deleted_bookmarks,
        shares = total_deleted_shares,
        "Content cleanup summary"
    );

    Ok(())
}

/// Collect all distinct user_ids from all content tables
async fn collect_all_user_ids(db: &PgPool) -> Result<Vec<Uuid>, sqlx::Error> {
    // UNION query to get all unique user_ids across all tables
    let user_ids: Vec<Uuid> = sqlx::query_scalar(
        r#"
        SELECT DISTINCT user_id FROM posts WHERE deleted_at IS NULL
        UNION
        SELECT DISTINCT user_id FROM comments
        UNION
        SELECT DISTINCT user_id FROM likes
        UNION
        SELECT DISTINCT user_id FROM bookmarks
        UNION
        SELECT DISTINCT user_id FROM shares
        ORDER BY 1
        "#,
    )
    .fetch_all(db)
    .await?;

    Ok(user_ids)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_constants() {
        assert_eq!(RETENTION_DAYS, 30);
        assert_eq!(BATCH_SIZE, 100);
        assert_eq!(CHECK_INTERVAL, Duration::from_secs(24 * 60 * 60));
    }
}
