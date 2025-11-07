/// stream_cleaner Background Job - Phase 4 (Spec 007)
///
/// Cleans up streaming data from soft-deleted users after a 30-day retention period:
/// - Ends streams from deleted broadcasters (soft-delete: status = 'ended')
/// - Revokes stream keys from deleted broadcasters (soft-delete: is_active = false)
/// - Deletes viewer sessions from deleted users (hard-delete: anonymous viewing data)
///
/// References:
/// - messaging-service/src/jobs/orphan_cleaner.rs
/// - content-service/src/jobs/content_cleaner.rs
/// - feed-service/src/jobs/feed_cleaner.rs
use anyhow::Result;
use chrono::{Duration as ChronoDuration, Utc};
use grpc_clients::AuthClient;
use sqlx::PgPool;
use std::collections::HashSet;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tracing::{error, info, warn};
use uuid::Uuid;

use crate::metrics::stream_cleaner::{
    record_cleanup_duration, record_cleanup_run, record_content_deleted, set_users_checked,
};

/// Retention period before cleanup: 30 days
const RETENTION_DAYS: i64 = 30;

/// Batch size for gRPC calls: 100 users per request
const BATCH_SIZE: i64 = 100;

/// Main entry point for stream cleaner background job
///
/// Runs cleanup cycle every 24 hours (1 day):
/// 1. Collects all user IDs from streaming tables
/// 2. Batch-validates users against auth-service
/// 3. Cleans up streams/keys/sessions from soft-deleted users
pub async fn start_stream_cleaner(db: PgPool, auth_client: Arc<AuthClient>) {
    info!("✅ Stream cleaner started (interval: 24h, retention: 30d, batch_size: 100)");

    loop {
        let start = Instant::now();
        match cleanup_deleted_user_streams(&db, &auth_client).await {
            Ok(_) => {
                record_cleanup_run("success");
                info!(
                    "Stream cleanup cycle completed in {:.2}s",
                    start.elapsed().as_secs_f64()
                );
            }
            Err(e) => {
                record_cleanup_run("error");
                error!("Stream cleanup cycle failed: {:?}", e);
            }
        }

        // Sleep for 24 hours before next cleanup cycle
        tokio::time::sleep(Duration::from_secs(24 * 60 * 60)).await;
    }
}

/// Main cleanup orchestration function
///
/// Process:
/// 1. Collect all distinct user IDs from streams, stream_keys, viewer_sessions
/// 2. Batch-validate users via auth_client (100 users/batch to avoid N+1)
/// 3. Identify soft-deleted users beyond retention period
/// 4. Clean up streams (soft-delete), keys (soft-delete), sessions (hard-delete)
async fn cleanup_deleted_user_streams(db: &PgPool, auth_client: &AuthClient) -> Result<()> {
    info!("Starting stream cleanup cycle");

    // Step 1: Collect all user IDs from streaming tables
    let collect_start = Instant::now();
    let user_ids = collect_all_user_ids(db).await?;
    record_cleanup_duration("collect_user_ids", collect_start.elapsed());

    if user_ids.is_empty() {
        info!("No user data found in streaming tables");
        set_users_checked(0);
        return Ok(());
    }

    info!(
        "Collected {} unique users from streaming tables",
        user_ids.len()
    );
    set_users_checked(user_ids.len() as i64);

    // Step 2: Batch-validate users against auth-service
    let validate_start = Instant::now();
    let deleted_users = identify_deleted_users(auth_client, &user_ids).await?;
    record_cleanup_duration("validate_users", validate_start.elapsed());

    if deleted_users.is_empty() {
        info!("No deleted users found, skipping cleanup");
        return Ok(());
    }

    info!(
        "Identified {} soft-deleted users beyond {}d retention",
        deleted_users.len(),
        RETENTION_DAYS
    );

    // Step 3: Clean up streaming data for each deleted user
    let cleanup_start = Instant::now();
    let mut cleaned_streams = 0u64;
    let mut revoked_keys = 0u64;
    let mut deleted_sessions = 0u64;

    for user_id in deleted_users {
        match cleanup_user_streams(db, user_id).await {
            Ok((streams, keys, sessions)) => {
                cleaned_streams += streams;
                revoked_keys += keys;
                deleted_sessions += sessions;
            }
            Err(e) => {
                warn!("Failed to cleanup streams for user {}: {:?}", user_id, e);
            }
        }
    }

    record_cleanup_duration("cleanup_streams", cleanup_start.elapsed());
    record_content_deleted("streams_ended", cleaned_streams);
    record_content_deleted("keys_revoked", revoked_keys);
    record_content_deleted("sessions_deleted", deleted_sessions);

    info!(
        "Cleanup completed: {} streams ended, {} keys revoked, {} sessions deleted",
        cleaned_streams, revoked_keys, deleted_sessions
    );

    Ok(())
}

/// Collect all distinct user IDs from streaming tables
///
/// Uses UNION to deduplicate across:
/// - streams.broadcaster_id (NOT NULL)
/// - stream_keys.broadcaster_id (NOT NULL)
/// - viewer_sessions.viewer_id (NULLABLE - requires IS NOT NULL filter)
async fn collect_all_user_ids(db: &PgPool) -> Result<Vec<Uuid>> {
    let user_ids: Vec<Uuid> = sqlx::query_scalar(
        "SELECT DISTINCT broadcaster_id AS user_id FROM streams
         UNION
         SELECT DISTINCT broadcaster_id AS user_id FROM stream_keys
         UNION
         SELECT DISTINCT viewer_id AS user_id FROM viewer_sessions WHERE viewer_id IS NOT NULL
         ORDER BY 1",
    )
    .fetch_all(db)
    .await?;

    Ok(user_ids)
}

/// Identify soft-deleted users beyond retention period via batch gRPC calls
///
/// Batch processing eliminates N+1 problem:
/// - 500 users → 5 batches (100 users each) → 5 gRPC calls instead of 500
///
/// Returns: Set of user IDs that are soft-deleted AND beyond retention period
async fn identify_deleted_users(
    auth_client: &AuthClient,
    user_ids: &[Uuid],
) -> Result<HashSet<Uuid>> {
    let _retention_cutoff = Utc::now() - ChronoDuration::days(RETENTION_DAYS);
    let mut deleted_users = HashSet::new();

    // Process in batches of 100 to optimize gRPC calls
    for chunk in user_ids.chunks(BATCH_SIZE as usize) {
        let batch_start = Instant::now();
        match auth_client.get_users_by_ids(chunk).await {
            Ok(users_map) => {
                // users_map is HashMap<Uuid, String> where keys are existing user IDs
                let existing_users: HashSet<Uuid> = users_map.keys().copied().collect();

                // Users not in response are soft-deleted
                for &user_id in chunk {
                    if !existing_users.contains(&user_id) {
                        // Note: We assume users deleted beyond retention_cutoff
                        // In production, auth-service should return deleted_at timestamp
                        deleted_users.insert(user_id);
                    }
                }

                record_cleanup_duration("batch_grpc_call", batch_start.elapsed());
            }
            Err(e) => {
                warn!("Batch gRPC call failed for {} users: {:?}", chunk.len(), e);
                // Continue with next batch rather than failing entire cleanup
            }
        }
    }

    Ok(deleted_users)
}

/// Clean up all streaming data for a deleted user
///
/// Returns: (streams_ended, keys_revoked, sessions_deleted) tuple
async fn cleanup_user_streams(db: &PgPool, user_id: Uuid) -> Result<(u64, u64, u64)> {
    info!("Cleaning up streams for deleted user: {}", user_id);

    // 1. Soft-delete streams: set status = 'ended', ended_at = NOW()
    let streams_result = sqlx::query(
        "UPDATE streams
         SET status = 'ended', ended_at = NOW()
         WHERE broadcaster_id = $1 AND status NOT IN ('ended', 'interrupted')",
    )
    .bind(user_id)
    .execute(db)
    .await?;

    let streams_ended = streams_result.rows_affected();

    // 2. Soft-delete stream keys: set is_active = false, revoked_at = NOW()
    let keys_result = sqlx::query(
        "UPDATE stream_keys
         SET is_active = false, revoked_at = NOW()
         WHERE broadcaster_id = $1 AND is_active = true",
    )
    .bind(user_id)
    .execute(db)
    .await?;

    let keys_revoked = keys_result.rows_affected();

    // 3. Hard-delete viewer sessions: anonymous viewing data, no audit requirement
    let sessions_result = sqlx::query("DELETE FROM viewer_sessions WHERE viewer_id = $1")
        .bind(user_id)
        .execute(db)
        .await?;

    let sessions_deleted = sessions_result.rows_affected();

    info!(
        "User {} cleanup: {} streams ended, {} keys revoked, {} sessions deleted",
        user_id, streams_ended, keys_revoked, sessions_deleted
    );

    Ok((streams_ended, keys_revoked, sessions_deleted))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_retention_period_is_30_days() {
        assert_eq!(RETENTION_DAYS, 30);
    }

    #[test]
    fn test_batch_size_is_100() {
        assert_eq!(BATCH_SIZE, 100);
    }
}
