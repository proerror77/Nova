use crate::models::Like;
use sqlx::{PgPool, Row};
use uuid::Uuid;

/// Create a new like on a post
/// Returns the created like, or an error if already liked
pub async fn create_like(
    pool: &PgPool,
    post_id: Uuid,
    user_id: Uuid,
) -> Result<Like, sqlx::Error> {
    let like = sqlx::query_as::<_, Like>(
        r#"
        INSERT INTO likes (post_id, user_id)
        VALUES ($1, $2)
        RETURNING id, post_id, user_id, created_at
        "#,
    )
    .bind(post_id)
    .bind(user_id)
    .fetch_one(pool)
    .await?;

    Ok(like)
}

/// Delete a like from a post
pub async fn delete_like(
    pool: &PgPool,
    post_id: Uuid,
    user_id: Uuid,
) -> Result<(), sqlx::Error> {
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
pub async fn find_like(
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

/// Count total likes for a post
pub async fn count_likes_by_post(pool: &PgPool, post_id: Uuid) -> Result<i64, sqlx::Error> {
    let row = sqlx::query(
        "SELECT COUNT(*) as count FROM likes WHERE post_id = $1",
    )
    .bind(post_id)
    .fetch_one(pool)
    .await?;

    Ok(row.get::<i64, _>("count"))
}

/// Get all users who liked a post
pub async fn get_post_likers(
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

/// Get all posts liked by a user
pub async fn get_user_likes(
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

/// Get like count for multiple posts
pub async fn count_likes_batch(
    pool: &PgPool,
    post_ids: &[Uuid],
) -> Result<Vec<(Uuid, i64)>, sqlx::Error> {
    let rows = sqlx::query(
        r#"
        SELECT post_id, COUNT(*) as count
        FROM likes
        WHERE post_id = ANY($1)
        GROUP BY post_id
        "#,
    )
    .bind(post_ids)
    .fetch_all(pool)
    .await?;

    let counts: Vec<(Uuid, i64)> = rows
        .into_iter()
        .map(|row| {
            let post_id: Uuid = row.get("post_id");
            let count: i64 = row.get("count");
            (post_id, count)
        })
        .collect();

    Ok(counts)
}
