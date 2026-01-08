use crate::models::{Post, PostImage, PostMetadata, UploadSession};
use chrono::{Duration, Utc};
use sqlx::{PgPool, Row};
use uuid::Uuid;

/// Create a new post with status "pending"
/// Returns the created post
pub async fn create_post(
    pool: &PgPool,
    user_id: Uuid,
    caption: Option<&str>,
    media_key: &str,
    media_type: &str,
) -> Result<Post, sqlx::Error> {
    // Note: media_urls should be empty for text-only posts (media_type='text')
    let post = sqlx::query_as::<_, Post>(
        r#"
        INSERT INTO posts (user_id, caption, media_key, media_type, media_urls, status)
        VALUES (
            $1,
            $2,
            $3,
            $4,
            CASE WHEN $4 = 'text' THEN '[]'::jsonb ELSE jsonb_build_array($3) END,
            'pending'
        )
        RETURNING id, user_id, content, caption, media_key, media_type, media_urls, status,
                  created_at, updated_at, deleted_at, soft_delete::text AS soft_delete
        "#,
    )
    .bind(user_id)
    .bind(caption)
    .bind(media_key)
    .bind(media_type)
    .fetch_one(pool)
    .await?;

    Ok(post)
}

/// Find a post by ID (excluding soft-deleted posts)
pub async fn find_post_by_id(pool: &PgPool, post_id: Uuid) -> Result<Option<Post>, sqlx::Error> {
    let post = sqlx::query_as::<_, Post>(
        r#"
        SELECT id, user_id, content, caption, media_key, media_type, media_urls, status,
               created_at, updated_at, deleted_at, soft_delete::text AS soft_delete
        FROM posts
        WHERE id = $1 AND deleted_at IS NULL
        "#,
    )
    .bind(post_id)
    .fetch_optional(pool)
    .await?;

    Ok(post)
}

/// Find all posts by a user (excluding soft-deleted)
/// Returns posts in descending order by creation date
pub async fn find_posts_by_user(
    pool: &PgPool,
    user_id: Uuid,
    limit: i64,
    offset: i64,
) -> Result<Vec<Post>, sqlx::Error> {
    let posts = sqlx::query_as::<_, Post>(
        r#"
        SELECT id, user_id, content, caption, media_key, media_type, media_urls, status,
               created_at, updated_at, deleted_at, soft_delete::text AS soft_delete
        FROM posts
        WHERE user_id = $1 AND deleted_at IS NULL
        ORDER BY created_at DESC
        LIMIT $2 OFFSET $3
        "#,
    )
    .bind(user_id)
    .bind(limit)
    .bind(offset)
    .fetch_all(pool)
    .await?;

    Ok(posts)
}

/// Count total posts for a user (excluding soft-deleted)
pub async fn count_posts_by_user(pool: &PgPool, user_id: Uuid) -> Result<i64, sqlx::Error> {
    let row = sqlx::query(
        "SELECT COUNT(*) as count FROM posts WHERE user_id = $1 AND deleted_at IS NULL",
    )
    .bind(user_id)
    .fetch_one(pool)
    .await?;

    Ok(row.get::<i64, _>("count"))
}

/// Fetch recent published posts for fallback feeds.
pub async fn get_recent_published_post_ids(
    pool: &PgPool,
    limit: i64,
    offset: i64,
) -> Result<Vec<Uuid>, sqlx::Error> {
    let rows = sqlx::query_as::<_, (Uuid,)>(
        r#"
        SELECT id
        FROM posts
        WHERE deleted_at IS NULL
          AND status = 'published'
        ORDER BY created_at DESC
        LIMIT $1 OFFSET $2
        "#,
    )
    .bind(limit)
    .bind(offset)
    .fetch_all(pool)
    .await?;

    Ok(rows.into_iter().map(|(id,)| id).collect())
}

/// Update post status
pub async fn update_post_status(
    pool: &PgPool,
    post_id: Uuid,
    status: &str,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE posts
        SET status = $1, updated_at = NOW()
        WHERE id = $2
        "#,
    )
    .bind(status)
    .bind(post_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Update post media_key
pub async fn update_post_media_key(
    pool: &PgPool,
    post_id: Uuid,
    media_key: &str,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE posts
        SET media_key = $1, updated_at = NOW()
        WHERE id = $2
        "#,
    )
    .bind(media_key)
    .bind(post_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Soft delete a post by setting soft_delete timestamp
pub async fn soft_delete_post(pool: &PgPool, post_id: Uuid) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE posts
        SET deleted_at = NOW(), updated_at = NOW()
        WHERE id = $1
        "#,
    )
    .bind(post_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Get post with all image URLs and metadata
pub async fn get_post_with_images(
    pool: &PgPool,
    post_id: Uuid,
) -> Result<
    Option<(
        Post,
        PostMetadata,
        Option<String>,
        Option<String>,
        Option<String>,
    )>,
    sqlx::Error,
> {
    let row = sqlx::query(
        r#"
        SELECT
            p.id, p.user_id, p.content, p.caption, p.media_key, p.media_type, p.media_urls, p.status,
            p.created_at, p.updated_at, p.deleted_at, p.soft_delete::text AS soft_delete, p.author_account_type,
            COALESCE(pm.like_count, 0) as like_count,
            COALESCE(pm.comment_count, 0) as comment_count,
            COALESCE(pm.view_count, 0) as view_count,
            COALESCE(pm.updated_at, p.created_at) as metadata_updated_at,
            (SELECT url FROM post_images WHERE post_id = p.id AND size_variant = 'thumbnail' AND status = 'completed' LIMIT 1) as thumbnail_url,
            (SELECT url FROM post_images WHERE post_id = p.id AND size_variant = 'medium' AND status = 'completed' LIMIT 1) as medium_url,
            (SELECT url FROM post_images WHERE post_id = p.id AND size_variant = 'original' AND status = 'completed' LIMIT 1) as original_url
        FROM posts p
        LEFT JOIN post_metadata pm ON p.id = pm.post_id
        WHERE p.id = $1 AND p.deleted_at IS NULL
        "#,
    )
    .bind(post_id)
    .fetch_optional(pool)
    .await?;

    if let Some(r) = row {
        let post = Post {
            id: r.get("id"),
            user_id: r.get("user_id"),
            content: r.get("content"),
            caption: r.get("caption"),
            media_key: r.get("media_key"),
            media_type: r.get("media_type"),
            media_urls: r.get("media_urls"),
            status: r.get("status"),
            created_at: r.get("created_at"),
            updated_at: r.get("updated_at"),
            deleted_at: r.get("deleted_at"),
            soft_delete: r.get("soft_delete"),
            author_account_type: r.get("author_account_type"),
        };

        let metadata = PostMetadata {
            post_id: r.get("id"),
            like_count: r.get("like_count"),
            comment_count: r.get("comment_count"),
            view_count: r.get("view_count"),
            updated_at: r.get("metadata_updated_at"),
        };

        let thumbnail_url: Option<String> = r.get("thumbnail_url");
        let medium_url: Option<String> = r.get("medium_url");
        let original_url: Option<String> = r.get("original_url");

        Ok(Some((
            post,
            metadata,
            thumbnail_url,
            medium_url,
            original_url,
        )))
    } else {
        Ok(None)
    }
}

// ============================================
// PostImage Operations
// ============================================

/// Create a post image variant record
pub async fn create_post_image(
    pool: &PgPool,
    post_id: Uuid,
    s3_key: &str,
    size_variant: &str,
) -> Result<PostImage, sqlx::Error> {
    let image = sqlx::query_as::<_, PostImage>(
        r#"
        INSERT INTO post_images (post_id, s3_key, size_variant, status)
        VALUES ($1, $2, $3, 'pending')
        RETURNING id, post_id, s3_key, status, size_variant, file_size, width, height, url, error_message, created_at, updated_at
        "#,
    )
    .bind(post_id)
    .bind(s3_key)
    .bind(size_variant)
    .fetch_one(pool)
    .await?;

    Ok(image)
}

/// Get all image variants for a post
pub async fn get_post_images(pool: &PgPool, post_id: Uuid) -> Result<Vec<PostImage>, sqlx::Error> {
    let images = sqlx::query_as::<_, PostImage>(
        r#"
        SELECT id, post_id, s3_key, status, size_variant, file_size, width, height, url, error_message, created_at, updated_at
        FROM post_images
        WHERE post_id = $1
        ORDER BY size_variant
        "#,
    )
    .bind(post_id)
    .fetch_all(pool)
    .await?;

    Ok(images)
}

/// Update post image status and metadata
pub async fn update_post_image(
    pool: &PgPool,
    image_id: Uuid,
    status: &str,
    url: Option<&str>,
    width: Option<i32>,
    height: Option<i32>,
    file_size: Option<i32>,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE post_images
        SET status = $1, url = $2, width = $3, height = $4, file_size = $5, updated_at = NOW()
        WHERE id = $6
        "#,
    )
    .bind(status)
    .bind(url)
    .bind(width)
    .bind(height)
    .bind(file_size)
    .bind(image_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Update post image error message (when processing fails)
pub async fn update_post_image_error(
    pool: &PgPool,
    image_id: Uuid,
    error_message: &str,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE post_images
        SET status = 'failed', error_message = $1, updated_at = NOW()
        WHERE id = $2
        "#,
    )
    .bind(error_message)
    .bind(image_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Check if all image variants for a post are completed
pub async fn all_images_completed(pool: &PgPool, post_id: Uuid) -> Result<bool, sqlx::Error> {
    let row = sqlx::query(
        r#"
        SELECT COUNT(*) as total,
               SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as completed
        FROM post_images
        WHERE post_id = $1
        "#,
    )
    .bind(post_id)
    .fetch_one(pool)
    .await?;

    let total: i64 = row.get("total");
    let completed: i64 = row.get("completed");

    Ok(total > 0 && total == completed)
}

// ============================================
// UploadSession Operations
// ============================================

/// Create an upload session with a time-limited token
pub async fn create_upload_session(
    pool: &PgPool,
    post_id: Uuid,
    upload_token: &str,
) -> Result<UploadSession, sqlx::Error> {
    let expires_at = Utc::now() + Duration::hours(1);

    let session = sqlx::query_as::<_, UploadSession>(
        r#"
        INSERT INTO upload_sessions (post_id, upload_token, expires_at)
        VALUES ($1, $2, $3)
        RETURNING id, post_id, upload_token, file_hash, expires_at, is_completed, created_at
        "#,
    )
    .bind(post_id)
    .bind(upload_token)
    .bind(expires_at)
    .fetch_one(pool)
    .await?;

    Ok(session)
}

/// Find upload session by token
pub async fn find_upload_session_by_token(
    pool: &PgPool,
    token: &str,
) -> Result<Option<UploadSession>, sqlx::Error> {
    let session = sqlx::query_as::<_, UploadSession>(
        r#"
        SELECT id, post_id, upload_token, file_hash, expires_at, is_completed, created_at
        FROM upload_sessions
        WHERE upload_token = $1 AND expires_at > NOW()
        "#,
    )
    .bind(token)
    .fetch_optional(pool)
    .await?;

    Ok(session)
}

/// Mark upload session as completed
pub async fn mark_upload_completed(pool: &PgPool, session_id: Uuid) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE upload_sessions
        SET is_completed = TRUE
        WHERE id = $1
        "#,
    )
    .bind(session_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Update upload session with file hash and size for audit trail
pub async fn update_session_file_hash(
    pool: &PgPool,
    session_id: Uuid,
    file_hash: &str,
    file_size: i64,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE upload_sessions
        SET file_hash = $1, file_size = $2
        WHERE id = $3
        "#,
    )
    .bind(file_hash)
    .bind(file_size)
    .bind(session_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Delete expired upload sessions (cleanup)
pub async fn cleanup_expired_sessions(pool: &PgPool) -> Result<u64, sqlx::Error> {
    let result = sqlx::query(
        r#"
        DELETE FROM upload_sessions
        WHERE expires_at < NOW() AND is_completed = FALSE
        "#,
    )
    .execute(pool)
    .await?;

    Ok(result.rows_affected())
}

// ============================================
// PostMetadata Operations
// ============================================

/// Get post metadata (engagement stats)
pub async fn get_post_metadata(
    pool: &PgPool,
    post_id: Uuid,
) -> Result<Option<PostMetadata>, sqlx::Error> {
    let metadata = sqlx::query_as::<_, PostMetadata>(
        r#"
        SELECT post_id, like_count, comment_count, view_count, updated_at
        FROM post_metadata
        WHERE post_id = $1
        "#,
    )
    .bind(post_id)
    .fetch_optional(pool)
    .await?;

    Ok(metadata)
}

/// Increment like count
pub async fn increment_like_count(pool: &PgPool, post_id: Uuid) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE post_metadata
        SET like_count = like_count + 1, updated_at = NOW()
        WHERE post_id = $1
        "#,
    )
    .bind(post_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Decrement like count
pub async fn decrement_like_count(pool: &PgPool, post_id: Uuid) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE post_metadata
        SET like_count = GREATEST(like_count - 1, 0), updated_at = NOW()
        WHERE post_id = $1
        "#,
    )
    .bind(post_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Increment comment count
pub async fn increment_comment_count(pool: &PgPool, post_id: Uuid) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE post_metadata
        SET comment_count = comment_count + 1, updated_at = NOW()
        WHERE post_id = $1
        "#,
    )
    .bind(post_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Decrement comment count
pub async fn decrement_comment_count(pool: &PgPool, post_id: Uuid) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE post_metadata
        SET comment_count = GREATEST(comment_count - 1, 0), updated_at = NOW()
        WHERE post_id = $1
        "#,
    )
    .bind(post_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Increment view count
pub async fn increment_view_count(pool: &PgPool, post_id: Uuid) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE post_metadata
        SET view_count = view_count + 1, updated_at = NOW()
        WHERE post_id = $1
        "#,
    )
    .bind(post_id)
    .execute(pool)
    .await?;

    Ok(())
}

// ============================================
// PostVideo Operations
// ============================================

/// Create a post_videos association (link video to post)
pub async fn create_post_video(
    pool: &PgPool,
    post_id: Uuid,
    video_id: Uuid,
    position: i32,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        INSERT INTO post_videos (post_id, video_id, position)
        VALUES ($1, $2, $3)
        "#,
    )
    .bind(post_id)
    .bind(video_id)
    .bind(position)
    .execute(pool)
    .await?;

    Ok(())
}

/// Get all videos for a post ordered by position
pub async fn get_post_videos(
    pool: &PgPool,
    post_id: Uuid,
) -> Result<Vec<(Uuid, i32)>, sqlx::Error> {
    let rows = sqlx::query(
        r#"
        SELECT pv.video_id, pv.position
        FROM post_videos pv
        WHERE pv.post_id = $1
        ORDER BY pv.position ASC
        "#,
    )
    .bind(post_id)
    .fetch_all(pool)
    .await?;

    let videos = rows
        .iter()
        .map(|r| {
            let video_id: Uuid = r.get("video_id");
            let position: i32 = r.get("position");
            (video_id, position)
        })
        .collect();

    Ok(videos)
}

/// Get video metadata for a post (with CDN URLs and details)
pub async fn get_post_videos_with_metadata(
    pool: &PgPool,
    post_id: Uuid,
) -> Result<
    Vec<(
        Uuid,
        String,
        Option<String>,
        Option<String>,
        Option<i32>,
        i32,
    )>,
    sqlx::Error,
> {
    let rows = sqlx::query(
        r#"
        SELECT
            v.id,
            v.id::text as video_id_str,
            v.cdn_url,
            v.thumbnail_url,
            v.duration_seconds,
            pv.position
        FROM post_videos pv
        JOIN videos v ON pv.video_id = v.id
        WHERE pv.post_id = $1
        ORDER BY pv.position ASC
        "#,
    )
    .bind(post_id)
    .fetch_all(pool)
    .await?;

    let videos = rows
        .iter()
        .map(|r| {
            let video_id: Uuid = r.get("id");
            let video_id_str: String = r.get("video_id_str");
            let cdn_url: Option<String> = r.get("cdn_url");
            let thumbnail_url: Option<String> = r.get("thumbnail_url");
            let duration_seconds: Option<i32> = r.get("duration_seconds");
            let position: i32 = r.get("position");
            (
                video_id,
                video_id_str,
                cdn_url,
                thumbnail_url,
                duration_seconds,
                position,
            )
        })
        .collect();

    Ok(videos)
}

/// Remove a video from a post
pub async fn remove_post_video(
    pool: &PgPool,
    post_id: Uuid,
    video_id: Uuid,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        DELETE FROM post_videos
        WHERE post_id = $1 AND video_id = $2
        "#,
    )
    .bind(post_id)
    .bind(video_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Check if post has any videos
pub async fn post_has_videos(pool: &PgPool, post_id: Uuid) -> Result<bool, sqlx::Error> {
    let row = sqlx::query(
        r#"
        SELECT EXISTS(SELECT 1 FROM post_videos WHERE post_id = $1) as has_videos
        "#,
    )
    .bind(post_id)
    .fetch_one(pool)
    .await?;

    Ok(row.get::<bool, _>("has_videos"))
}
