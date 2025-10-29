/// Video repository - database operations for videos
///
/// Provides reusable SQL helpers for the `videos` table so the rest of the
/// service can depend on a consistent data-access surface.
use crate::error::Result;
use crate::models::Video;
use sqlx::PgPool;
use uuid::Uuid;

/// Fetch the most recent videos (ignoring soft-deleted entries).
pub async fn list_recent(pool: &PgPool, limit: i64) -> Result<Vec<Video>> {
    let videos = sqlx::query_as::<_, Video>(
        "SELECT id, creator_id, title, description, duration_seconds,
                cdn_url, thumbnail_url, status, visibility,
                created_at, updated_at
         FROM videos
         WHERE deleted_at IS NULL
         ORDER BY created_at DESC
         LIMIT $1",
    )
    .bind(limit)
    .fetch_all(pool)
    .await?;

    Ok(videos)
}

/// Retrieve a single video by identifier.
pub async fn get_video(pool: &PgPool, video_id: Uuid) -> Result<Option<Video>> {
    let video = sqlx::query_as::<_, Video>(
        "SELECT id, creator_id, title, description, duration_seconds,
                cdn_url, thumbnail_url, status, visibility,
                created_at, updated_at
         FROM videos
         WHERE id = $1 AND deleted_at IS NULL",
    )
    .bind(video_id)
    .fetch_optional(pool)
    .await?;

    Ok(video)
}

/// Retrieve videos for a specific creator.
pub async fn list_by_creator(pool: &PgPool, creator_id: Uuid, limit: i32) -> Result<Vec<Video>> {
    let videos = sqlx::query_as::<_, Video>(
        "SELECT id, creator_id, title, description, duration_seconds,
                cdn_url, thumbnail_url, status, visibility,
                created_at, updated_at
         FROM videos
         WHERE creator_id = $1 AND deleted_at IS NULL
         ORDER BY created_at DESC
         LIMIT $2",
    )
    .bind(creator_id)
    .bind(limit)
    .fetch_all(pool)
    .await?;

    Ok(videos)
}

/// Insert a new video row and return the persisted entity.
pub async fn create_video(
    pool: &PgPool,
    video_id: Uuid,
    creator_id: Uuid,
    title: &str,
    description: Option<&str>,
    visibility: &str,
    status: &str,
) -> Result<Video> {
    let video = sqlx::query_as::<_, Video>(
        "INSERT INTO videos (
            id, creator_id, title, description, duration_seconds,
            cdn_url, thumbnail_url, status, visibility, created_at, updated_at
        ) VALUES ($1, $2, $3, $4, 0, NULL, NULL, $5, $6, NOW(), NOW())
        RETURNING id, creator_id, title, description, duration_seconds,
                  cdn_url, thumbnail_url, status, visibility,
                  created_at, updated_at",
    )
    .bind(video_id)
    .bind(creator_id)
    .bind(title)
    .bind(description)
    .bind(status)
    .bind(visibility)
    .fetch_one(pool)
    .await?;

    Ok(video)
}

/// Update a video's metadata fields and return the refreshed entity.
pub async fn update_video(
    pool: &PgPool,
    video_id: Uuid,
    title: &str,
    description: Option<&str>,
    visibility: &str,
) -> Result<Video> {
    let video = sqlx::query_as::<_, Video>(
        "UPDATE videos
         SET title = $2, description = $3, visibility = $4, updated_at = NOW()
         WHERE id = $1 AND deleted_at IS NULL
         RETURNING id, creator_id, title, description, duration_seconds,
                   cdn_url, thumbnail_url, status, visibility,
                   created_at, updated_at",
    )
    .bind(video_id)
    .bind(title)
    .bind(description)
    .bind(visibility)
    .fetch_one(pool)
    .await?;

    Ok(video)
}

/// Soft delete a video by setting `deleted_at`.
pub async fn soft_delete(pool: &PgPool, video_id: Uuid) -> Result<bool> {
    let result = sqlx::query(
        "UPDATE videos
         SET deleted_at = NOW(), updated_at = NOW()
         WHERE id = $1 AND deleted_at IS NULL",
    )
    .bind(video_id)
    .execute(pool)
    .await?;

    Ok(result.rows_affected() > 0)
}

/// Update only the status column.
pub async fn update_status(pool: &PgPool, video_id: Uuid, status: &str) -> Result<bool> {
    let result = sqlx::query(
        "UPDATE videos
         SET status = $2, updated_at = NOW()
         WHERE id = $1 AND deleted_at IS NULL",
    )
    .bind(video_id)
    .bind(status)
    .execute(pool)
    .await?;

    Ok(result.rows_affected() > 0)
}
