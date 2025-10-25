use crate::models::Like;
use sqlx::{PgPool, Row};
use uuid::Uuid;

/// Create a new like on a post
pub async fn create_like(
    pool: &PgPool,
    post_id: Uuid,
    user_id: Uuid,
) -> Result<Like, sqlx::Error> {
    let like = sqlx::query_as::<_, Like>(
        r#"
        INSERT INTO likes (post_id, user_id)
        VALUES ($1, $2)
        ON CONFLICT DO NOTHING
        RETURNING id, post_id, user_id, created_at
        "#,
    )
    .bind(post_id)
    .bind(user_id)
    .fetch_optional(pool)
    .await?;

    match like {
        Some(l) => Ok(l),
        None => {
            // If conflict, return the existing like
            get_like_by_post_and_user(pool, post_id, user_id)
                .await?
                .ok_or_else(|| sqlx::Error::RowNotFound)
        }
    }
}

/// Delete a like
pub async fn delete_like(pool: &PgPool, post_id: Uuid, user_id: Uuid) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        DELETE FROM likes
        WHERE post_id = $1 AND user_id = $2
        "#,
    )
    .bind(post_id)
    .bind(user_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Check if a user has liked a post
pub async fn has_liked(
    pool: &PgPool,
    post_id: Uuid,
    user_id: Uuid,
) -> Result<bool, sqlx::Error> {
    let row = sqlx::query("SELECT EXISTS(SELECT 1 FROM likes WHERE post_id = $1 AND user_id = $2)")
        .bind(post_id)
        .bind(user_id)
        .fetch_one(pool)
        .await?;

    Ok(row.get::<bool, _>(0))
}

/// Get a like by post and user
pub async fn get_like_by_post_and_user(
    pool: &PgPool,
    post_id: Uuid,
    user_id: Uuid,
) -> Result<Option<Like>, sqlx::Error> {
    let like = sqlx::query_as::<_, Like>(
        r#"
        SELECT id, post_id, user_id, created_at
        FROM likes
        WHERE post_id = $1 AND user_id = $2
        "#,
    )
    .bind(post_id)
    .bind(user_id)
    .fetch_optional(pool)
    .await?;

    Ok(like)
}

/// Get all likes for a post
pub async fn get_likes_by_post(
    pool: &PgPool,
    post_id: Uuid,
    limit: i64,
    offset: i64,
) -> Result<Vec<Like>, sqlx::Error> {
    let likes = sqlx::query_as::<_, Like>(
        r#"
        SELECT id, post_id, user_id, created_at
        FROM likes
        WHERE post_id = $1
        ORDER BY created_at DESC
        LIMIT $2 OFFSET $3
        "#,
    )
    .bind(post_id)
    .bind(limit)
    .bind(offset)
    .fetch_all(pool)
    .await?;

    Ok(likes)
}

/// Count likes for a post
pub async fn count_likes_by_post(pool: &PgPool, post_id: Uuid) -> Result<i32, sqlx::Error> {
    let row = sqlx::query("SELECT COUNT(*) as count FROM likes WHERE post_id = $1")
        .bind(post_id)
        .fetch_one(pool)
        .await?;

    Ok(row.get::<i32, _>("count"))
}

/// Get likes for a user
pub async fn get_likes_by_user(
    pool: &PgPool,
    user_id: Uuid,
    limit: i64,
    offset: i64,
) -> Result<Vec<Like>, sqlx::Error> {
    let likes = sqlx::query_as::<_, Like>(
        r#"
        SELECT id, post_id, user_id, created_at
        FROM likes
        WHERE user_id = $1
        ORDER BY created_at DESC
        LIMIT $2 OFFSET $3
        "#,
    )
    .bind(user_id)
    .bind(limit)
    .bind(offset)
    .fetch_all(pool)
    .await?;

    Ok(likes)
}
