use crate::models::video::{VideoEntity, VideoEngagementEntity};
use chrono::Utc;
use sqlx::{PgPool, Row};
use uuid::Uuid;

pub async fn create_video(
    pool: &PgPool,
    creator_id: Uuid,
    title: &str,
    description: Option<&str>,
    hashtags: &serde_json::Value,
    visibility: &str,
) -> Result<VideoEntity, sqlx::Error> {
    sqlx::query_as::<_, VideoEntity>(
        r#"
        INSERT INTO videos (
            creator_id, title, description, duration_seconds, upload_url, cdn_url, thumbnail_url,
            status, content_type, hashtags, visibility, allow_comments, allow_duet, allow_react
        ) VALUES (
            $1, $2, $3, $4, NULL, NULL, NULL,
            'processing', 'original', $5, $6, TRUE, TRUE, TRUE
        )
        RETURNING id, creator_id, title, description, duration_seconds, upload_url, cdn_url,
                  thumbnail_url, status, content_type, hashtags, visibility,
                  allow_comments, allow_duet, allow_react, created_at, published_at,
                  archived_at, deleted_at, updated_at
        "#,
    )
    .bind(creator_id)
    .bind(title)
    .bind(description)
    .bind(1_i32) // minimal positive duration, real value set after probe
    .bind(hashtags)
    .bind(visibility)
    .fetch_one(pool)
    .await
}

pub async fn get_video(pool: &PgPool, id: Uuid) -> Result<Option<VideoEntity>, sqlx::Error> {
    sqlx::query_as::<_, VideoEntity>(
        r#"
        SELECT id, creator_id, title, description, duration_seconds, upload_url, cdn_url,
               thumbnail_url, status, content_type, hashtags, visibility,
               allow_comments, allow_duet, allow_react, created_at, published_at,
               archived_at, deleted_at, updated_at
        FROM videos WHERE id = $1 AND deleted_at IS NULL
        "#,
    )
    .bind(id)
    .fetch_optional(pool)
    .await
}

pub async fn update_video(
    pool: &PgPool,
    id: Uuid,
    title: Option<&str>,
    description: Option<&str>,
    hashtags: Option<serde_json::Value>,
    visibility: Option<&str>,
) -> Result<VideoEntity, sqlx::Error> {
    // Simple update with COALESCE
    sqlx::query_as::<_, VideoEntity>(
        r#"
        UPDATE videos SET
            title = COALESCE($2, title),
            description = COALESCE($3, description),
            hashtags = COALESCE($4, hashtags),
            visibility = COALESCE($5, visibility),
            updated_at = NOW()
        WHERE id = $1 AND deleted_at IS NULL
        RETURNING id, creator_id, title, description, duration_seconds, upload_url, cdn_url,
                  thumbnail_url, status, content_type, hashtags, visibility,
                  allow_comments, allow_duet, allow_react, created_at, published_at,
                  archived_at, deleted_at, updated_at
        "#,
    )
    .bind(id)
    .bind(title)
    .bind(description)
    .bind(hashtags)
    .bind(visibility)
    .fetch_one(pool)
    .await
}

pub async fn soft_delete_video(pool: &PgPool, id: Uuid) -> Result<bool, sqlx::Error> {
    let res = sqlx::query(
        r#"UPDATE videos SET status = 'deleted', deleted_at = NOW() WHERE id = $1 AND deleted_at IS NULL"#,
    )
    .bind(id)
    .execute(pool)
    .await?;
    Ok(res.rows_affected() > 0)
}

pub async fn upsert_engagement(
    pool: &PgPool,
    id: Uuid,
    like_delta: i64,
) -> Result<VideoEngagementEntity, sqlx::Error> {
    // Ensure row
    sqlx::query(
        r#"INSERT INTO video_engagement (video_id) VALUES ($1) ON CONFLICT (video_id) DO NOTHING"#,
    )
    .bind(id)
    .execute(pool)
    .await?;
    // Update likes
    sqlx::query_as::<_, VideoEngagementEntity>(
        r#"
        UPDATE video_engagement SET like_count = GREATEST(like_count + $2, 0), last_updated = NOW()
        WHERE video_id = $1
        RETURNING video_id, view_count, like_count, share_count, comment_count, completion_rate, avg_watch_seconds, last_updated
        "#,
    )
    .bind(id)
    .bind(like_delta)
    .fetch_one(pool)
    .await
}

pub async fn increment_share(pool: &PgPool, id: Uuid) -> Result<VideoEngagementEntity, sqlx::Error> {
    sqlx::query(
        r#"INSERT INTO video_engagement (video_id) VALUES ($1) ON CONFLICT (video_id) DO NOTHING"#,
    )
    .bind(id)
    .execute(pool)
    .await?;
    sqlx::query_as::<_, VideoEngagementEntity>(
        r#"
        UPDATE video_engagement SET share_count = share_count + 1, last_updated = NOW()
        WHERE video_id = $1
        RETURNING video_id, view_count, like_count, share_count, comment_count, completion_rate, avg_watch_seconds, last_updated
        "#,
    )
    .bind(id)
    .fetch_one(pool)
    .await
}

pub async fn upsert_pipeline_status(
    pool: &PgPool,
    video_id: Uuid,
    stage: &str,
    progress: i32,
    current_step: &str,
    error: Option<&str>,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        INSERT INTO video_pipeline_state (video_id, stage, progress_percent, current_step, error)
        VALUES ($1, $2, $3, $4, $5)
        ON CONFLICT (video_id)
        DO UPDATE SET stage = EXCLUDED.stage,
                      progress_percent = EXCLUDED.progress_percent,
                      current_step = EXCLUDED.current_step,
                      error = EXCLUDED.error,
                      updated_at = NOW()
        "#,
    )
    .bind(video_id)
    .bind(stage)
    .bind(progress)
    .bind(current_step)
    .bind(error)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn get_pipeline_status(
    pool: &PgPool,
    video_id: Uuid,
) -> Result<Option<(String, i32, String, Option<String>)>, sqlx::Error> {
    let row_opt = sqlx::query(
        r#"SELECT stage, progress_percent, current_step, error FROM video_pipeline_state WHERE video_id = $1"#,
    )
    .bind(video_id)
    .fetch_optional(pool)
    .await?;
    Ok(row_opt.map(|r| (r.get("stage"), r.get("progress_percent"), r.get("current_step"), r.get("error"))))
}
