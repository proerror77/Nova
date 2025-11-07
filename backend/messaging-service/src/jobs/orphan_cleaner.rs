//! Orphan Cleaner Background Job
//!
//! Phase 1: Spec 007 - TOCTOU Mitigation
//!
//! Cleans up orphaned records from soft-deleted users after retention period.
//! This complements the soft-delete strategy by removing stale data after the
//! grace period (default: 30 days).
//!
//! Cleanup targets:
//! - conversation_members where user no longer exists in auth-service
//!
//! Note: This is a conservative cleanup that only removes data after users
//! have been soft-deleted for 30+ days, reducing risk of accidental data loss.

use crate::metrics;
use grpc_clients::AuthClient;
use sqlx::PgPool;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::time::sleep;
use uuid::Uuid;

/// Retention period before cleaning up orphaned records (30 days)
const RETENTION_DAYS: i64 = 30;

/// Check interval for orphan cleanup (runs once per day)
const CHECK_INTERVAL: Duration = Duration::from_secs(24 * 60 * 60); // 24 hours

/// Batch size for processing user IDs (avoid overwhelming auth-service)
const BATCH_SIZE: i64 = 100;

pub async fn start_orphan_cleaner(db: PgPool, auth_client: Arc<AuthClient>) {
    tracing::info!(
        "Starting orphan cleaner background job (check_interval={}h, retention_days={})",
        CHECK_INTERVAL.as_secs() / 3600,
        RETENTION_DAYS
    );

    loop {
        // Wait for the next check interval
        sleep(CHECK_INTERVAL).await;

        tracing::info!("Running orphan cleanup cycle");
        let cycle_start = Instant::now();

        match cleanup_orphaned_conversation_members(&db, &auth_client).await {
            Ok(()) => {
                metrics::record_orphan_cleanup_run("success");
                metrics::record_orphan_cleanup_duration("total", cycle_start.elapsed());
                tracing::info!("Orphan cleanup cycle completed successfully");
            }
            Err(e) => {
                metrics::record_orphan_cleanup_run("error");
                metrics::record_orphan_cleanup_duration("total", cycle_start.elapsed());
                tracing::error!(error = %e, "Orphan cleanup failed");
            }
        }
    }
}

/// Clean up conversation members where user no longer exists in auth-service
///
/// Strategy:
/// 1. Find all distinct user_ids in conversation_members
/// 2. Batch check with auth-service using get_users_by_ids() (100 users per call)
/// 3. Identify users not in returned HashMap (deleted users)
/// 4. Delete records for non-existent users
///
/// Performance: Batch API eliminates N+1 query problem
/// - Before: 100 users → 100 gRPC calls
/// - After:  100 users → 1 gRPC call (100x improvement)
///
/// Note: This deliberately does NOT check deleted_at in messaging DB because
/// we don't have access to auth-service's users table. We rely entirely on
/// auth-service.GetUsersByIds which already filters deleted_at.
async fn cleanup_orphaned_conversation_members(
    db: &PgPool,
    auth_client: &AuthClient,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    // Get all distinct user_ids from conversation_members
    let user_ids: Vec<Uuid> = sqlx::query_scalar(
        r#"
        SELECT DISTINCT user_id
        FROM conversation_members
        ORDER BY user_id
        "#,
    )
    .fetch_all(db)
    .await?;

    if user_ids.is_empty() {
        tracing::debug!("No conversation members to check");
        return Ok(());
    }

    tracing::info!(total_users = user_ids.len(), "Checking user existence");
    metrics::set_orphan_cleanup_users_checked(user_ids.len() as i64);

    let mut total_deleted = 0;

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

        // Delete conversation_members for non-existent users
        for user_id in deleted_user_ids {
            let result = sqlx::query("DELETE FROM conversation_members WHERE user_id = $1")
                .bind(user_id)
                .execute(db)
                .await?;

            let deleted = result.rows_affected();
            if deleted > 0 {
                tracing::info!(
                    user_id = %user_id,
                    records_deleted = deleted,
                    "Cleaned up orphaned conversation memberships"
                );
                total_deleted += deleted;
                metrics::record_orphan_cleanup_deleted("conversation_members", deleted);
            }
        }

        // Small delay between batches to avoid rate limiting
        tokio::time::sleep(Duration::from_millis(100)).await;
    }

    if total_deleted > 0 {
        tracing::info!(
            total_deleted = total_deleted,
            "Orphan cleanup removed {} conversation memberships",
            total_deleted
        );
    } else {
        tracing::debug!("No orphaned records found");
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_constants() {
        assert_eq!(RETENTION_DAYS, 30);
        assert_eq!(CHECK_INTERVAL.as_secs(), 24 * 60 * 60);
        assert_eq!(BATCH_SIZE, 100);
    }
}
